package io.proximi.flutter_proximiio_map

import android.content.Context
import android.view.View
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView
import io.proximi.map.core.FloorKey
import io.proximi.map.core.HeadingAim
import io.proximi.map.core.JourneyOrderProposal
import io.proximi.map.core.RouteFollowRules
import io.proximi.map.live.JourneyNavigator
import io.proximi.map.live.MapOptions
import io.proximi.map.live.ProximiioMapSession
import io.proximi.map.live.ProximiioMapView
import io.proximi.sdk.Proximiio
import io.proximi.sdk.computeRoute
import io.proximi.sdk.core.model.ProximiioCoordinate
import io.proximi.sdk.wayfinding.WayfindingRoutingError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The map's event channel. On listen it asks the controller for the current state, because the
 * session's StateFlows deliver their first values before Dart listens.
 */
internal class MapEventsRelay : MapEventsStreamHandler() {
  var sink: PigeonEventSink<MapMsgEvent>? = null
  var onAttach: (() -> Unit)? = null
  override fun onListen(p0: Any?, sink: PigeonEventSink<MapMsgEvent>) {
    this.sink = sink
    onAttach?.invoke()
  }
  override fun onCancel(p0: Any?) { sink = null }
}

internal class JourneyEventsRelay : JourneyEventsStreamHandler() {
  var sink: PigeonEventSink<MapMsgJourneyEvent>? = null
  var onAttach: (() -> Unit)? = null
  override fun onListen(p0: Any?, sink: PigeonEventSink<MapMsgJourneyEvent>) {
    this.sink = sink
    onAttach?.invoke()
  }
  override fun onCancel(p0: Any?) { sink = null }
}

/**
 * One map: its view, session, state collection and journey. Everything runs on the main thread.
 *
 * The view follows the activity lifecycle through a view-tree owner set before it is attached
 * (a plain FlutterActivity provides none). The host owns the session, so dispose closes it.
 */
internal class MapController(
  context: Context,
  private val handle: Long,
  options: MapOptions,
  sdk: Proximiio,
  private val messenger: BinaryMessenger,
  lifecycle: Lifecycle?,
) : PlatformView, MapHostApi {
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  private val session = ProximiioMapSession(sdk, context, options)
  private val mapView = ProximiioMapView(context, session)
  private val mapEvents = MapEventsRelay()
  private val journeyEvents = JourneyEventsRelay()
  private var navigator: JourneyNavigator? = null
  private var navigatorJobs: List<Job> = emptyList()
  private val proposals = mutableMapOf<Long, JourneyOrderProposal>()
  private var nextProposalId = 1L
  private var disposed = false

  init {
    if (lifecycle != null) {
      mapView.setViewTreeLifecycleOwner(object : LifecycleOwner {
        override val lifecycle: Lifecycle = lifecycle
      })
    }
    val suffix = handle.toString()
    MapHostApi.setUp(messenger, this, suffix)
    MapEventsStreamHandler.register(messenger, mapEvents, suffix)
    JourneyEventsStreamHandler.register(messenger, journeyEvents, suffix)
    mapEvents.onAttach = ::sendSnapshot
    journeyEvents.onAttach = ::sendJourneyState
    observeSession()
    session.startIfNeeded()
  }

  /** The current state, for a listener that attached after the first values. */
  private fun sendSnapshot() {
    send(MapMsgFloorsChanged(floors = session.floors.value.map(MapMappers::floor)))
    send(MapMsgSelectedFloorChanged(level = session.selectedFloor.value.level, isPinned = session.isFloorPinned.value))
    send(MapMsgCameraModeChanged(mode = MapMappers.cameraMode(session.cameraMode.value)))
    send(MapMappers.styleSource(session.styleSource.value))
    send(MapMsgErrorChanged(message = session.lastError.value))
    send(
      MapMsgGuidanceChanged(
        guidance = session.guidance.value?.let { MapMappers.guidance(it, session.guidanceText.text(it)) },
      ),
    )
    if (session.isCameraReady.value) send(MapMsgCameraReady(isReady = true))
  }

  override fun getView(): View = mapView

  private fun send(event: MapMsgEvent) {
    mapEvents.sink?.success(event)
  }

  private fun send(event: MapMsgJourneyEvent) {
    journeyEvents.sink?.success(event)
  }

  private fun <T> collect(flow: Flow<T>, action: (T) -> Unit): Job = scope.launch { flow.collect { action(it) } }

  private fun observeSession() {
    collect(session.floors) { floors -> send(MapMsgFloorsChanged(floors = floors.map(MapMappers::floor))) }
    collect(combine(session.selectedFloor, session.isFloorPinned) { floor, pinned -> floor to pinned }) { (floor, pinned) ->
      send(MapMsgSelectedFloorChanged(level = floor.level, isPinned = pinned))
    }
    collect(session.cameraMode) { send(MapMsgCameraModeChanged(mode = MapMappers.cameraMode(it))) }
    scope.launch {
      session.isCameraReady.filter { it }.first()
      send(MapMsgCameraReady(isReady = true))
    }
    collect(session.styleSource) { send(MapMappers.styleSource(it)) }
    collect(session.lastError) { send(MapMsgErrorChanged(message = it)) }
    collect(session.guidance) { guidance ->
      send(MapMsgGuidanceChanged(guidance = guidance?.let { MapMappers.guidance(it, session.guidanceText.text(it)) }))
    }
    session.onFeatureTap = { ids, coordinate ->
      send(MapMsgFeatureTapped(featureIds = ids, coordinate = MapMappers.msg(coordinate)))
    }
  }

  // region Options, camera, floors

  override fun setOptions(options: MapMsgOptions) {
    session.options = MapMappers.options(options)
  }

  override fun cameraState() = MapMsgCameraState(
    center = session.camera.center?.let(MapMappers::msg),
    zoom = session.camera.zoomLevel,
    direction = session.camera.direction,
    mode = MapMappers.cameraMode(session.cameraMode.value),
  )

  override fun setCenter(center: MapMsgCoordinate, zoom: Double?, animated: Boolean) {
    if (zoom == null) {
      session.camera.setCenter(MapMappers.mapCoordinate(center), animated)
    } else {
      session.camera.setCenter(MapMappers.mapCoordinate(center), zoom, animated)
    }
  }

  override fun setZoom(zoom: Double, animated: Boolean) = session.camera.setZoom(zoom, animated)

  override fun zoomBy(delta: Double, animated: Boolean) = session.camera.zoomBy(delta, animated)

  override fun fitCoordinates(coordinates: List<MapMsgCoordinate>, animated: Boolean) =
    session.camera.fit(coordinates = coordinates.map(MapMappers::mapCoordinate), animated = animated)

  override fun setHeading(degrees: Double?) = session.setHeading(degrees?.let { HeadingAim(it) })

  override fun recentre(zoom: Double?, withHeading: Boolean?) = session.recentre(zoom, withHeading)

  override fun showVenue(animated: Boolean) = session.showVenue(animated)

  override fun floors(): List<MapMsgFloor> = session.floors.value.map(MapMappers::floor)

  override fun selectedFloor(): Double = session.selectedFloor.value.level

  override fun selectFloor(level: Double) = session.select(FloorKey(level))

  override fun followMyFloor() = session.followMyFloor()

  override fun setHiddenFeatureIds(ids: List<String>) {
    session.hiddenFeatureIds = ids.toSet()
  }

  override fun clearTrail() = session.clearTrail()

  // endregion

  // region Routes and guidance

  override fun showRoute(
    from: MapMsgCoordinate,
    fromLevel: Double,
    to: MapMsgCoordinate,
    toLevel: Double,
    options: MapMsgRouteOptions,
    callback: (Result<MapMsgRoute>) -> Unit,
  ) {
    val sdk = session.sdk
    if (sdk == null) {
      callback(Result.failure(MapFlutterError("notConfigured", "The map has no SDK instance.")))
      return
    }
    scope.launch {
      val result = try {
        // The Android router is synchronous; it runs off the main thread.
        val route = withContext(Dispatchers.Default) {
          sdk.computeRoute(
            from = ProximiioCoordinate(from.latitude, from.longitude),
            fromLevel = fromLevel,
            to = ProximiioCoordinate(to.latitude, to.longitude),
            toLevel = toLevel,
            options = MapMappers.routeOptions(options),
          )
        }
        session.setRoute(route)
        Result.success(MapMappers.route(route))
      } catch (error: CancellationException) {
        throw error
      } catch (error: Throwable) {
        Result.failure(flutterError(error))
      }
      callback(result)
    }
  }

  override fun clearRoute() = session.clearRoute()

  override fun setGuidanceRules(rules: MapMsgFollowRules?) {
    session.guidanceRules = rules?.let(MapMappers::followRules)
  }

  override fun instructionText(destinationTitle: String?): String? = session.instructionText(destinationTitle)

  // endregion

  // region Journey

  private fun requireNavigator(): JourneyNavigator =
    navigator ?: throw MapFlutterError("noJourney", "No journey is running.")

  private fun <T> runJourney(callback: (Result<T>) -> Unit, body: suspend (JourneyNavigator) -> T) {
    scope.launch {
      val result = try {
        Result.success(body(requireNavigator()))
      } catch (error: CancellationException) {
        throw error
      } catch (error: Throwable) {
        Result.failure(flutterError(error))
      }
      callback(result)
    }
  }

  override fun startJourney(
    journey: MapMsgJourney,
    rules: MapMsgJourneyRules,
    routeOptions: MapMsgRouteOptions,
    callback: (Result<Unit>) -> Unit,
  ) {
    endNavigator()
    val navigator = try {
      JourneyNavigator(
        session = session,
        journey = MapMappers.journey(journey),
        rules = MapMappers.rules(rules),
        guidanceRules = session.guidanceRules ?: RouteFollowRules.VENUE_WALK,
      )
    } catch (error: Throwable) {
      callback(Result.failure(flutterError(error)))
      return
    }
    this.navigator = navigator
    observe(navigator)
    scope.launch {
      val result = try {
        navigator.setRouteOptions(MapMappers.routeOptions(routeOptions))
        navigator.start()
        Result.success(Unit)
      } catch (error: CancellationException) {
        throw error
      } catch (error: Throwable) {
        Result.failure(flutterError(error))
      }
      callback(result)
    }
  }

  private fun observe(navigator: JourneyNavigator) {
    val changes = merge(
      navigator.journey.map { },
      navigator.overview.map { },
      navigator.deviation.map { },
      navigator.noRouteReasons.map { },
    )
    navigatorJobs = listOf(
      collect(changes) { sendJourneyState() },
      collect(navigator.guidance) { guidance ->
        send(
          MapMsgJourneyGuidanceChanged(
            guidance = guidance?.let {
              MapMsgJourneyGuidance(guidance = MapMappers.guidance(it, session.guidanceText.text(it)))
            },
          ),
        )
      },
      collect(navigator.events) { send(MapMappers.notice(it)) },
    )
    navigator.onCue = { cue ->
      send(MapMsgJourneyCue(kind = MapMappers.camelName(cue.kind), text = cue.text, distanceMeters = cue.distanceMeters))
    }
  }

  private fun state(navigator: JourneyNavigator) = MapMsgJourneyState(
    journey = MapMappers.msg(navigator.journey.value),
    overview = MapMappers.overview(navigator.overview.value),
    deviation = navigator.deviation.value?.let(MapMappers::deviation),
    activeStopId = navigator.activeStop?.id,
    detourStopId = navigator.detourStop?.id,
    hasArrived = navigator.hasArrived,
    isFinished = navigator.isFinished,
    noRouteStopIds = navigator.noRouteReasons.value.mapValues { MapMappers.caseName(it.value) },
  )

  private fun sendJourneyState() {
    val navigator = navigator ?: return
    send(MapMsgJourneyStateChanged(state = state(navigator)))
  }

  private fun endNavigator() {
    navigator?.let {
      it.onCue = null
      it.end()
    }
    navigator = null
    navigatorJobs.forEach { it.cancel() }
    navigatorJobs = emptyList()
    proposals.clear()
  }

  override fun endJourney() = endNavigator()

  override fun journeyState(): MapMsgJourneyState? = navigator?.let(::state)

  override fun advance(callback: (Result<Unit>) -> Unit) = runJourney(callback) { it.advance() }

  override fun skip(callback: (Result<Unit>) -> Unit) = runJourney(callback) { it.skip() }

  override fun skipStop(stopId: String, callback: (Result<Boolean>) -> Unit) = runJourney(callback) { it.skip(stopId) }

  override fun markDone(stopId: String, callback: (Result<Boolean>) -> Unit) =
    runJourney(callback) { it.markDone(stopId) }

  override fun reopen(stopId: String, callback: (Result<Boolean>) -> Unit) = runJourney(callback) { it.reopen(stopId) }

  override fun activate(stopId: String, callback: (Result<Boolean>) -> Unit) =
    runJourney(callback) { it.activate(stopId) }

  override fun detour(stop: MapMsgStop, callback: (Result<Unit>) -> Unit) =
    runJourney(callback) { it.detour(MapMappers.stop(stop)) }

  override fun cancelDetour(callback: (Result<Unit>) -> Unit) = runJourney(callback) { it.cancelDetour() }

  override fun moveStop(stopId: String, toIndex: Long, callback: (Result<Unit>) -> Unit) =
    runJourney(callback) { it.move(stopId, toIndex.toInt()) }

  override fun addStop(stop: MapMsgStop, callback: (Result<Boolean>) -> Unit) =
    runJourney(callback) { it.add(MapMappers.stop(stop)) }

  override fun insertStop(stop: MapMsgStop, index: Long, callback: (Result<Boolean>) -> Unit) =
    runJourney(callback) { it.insert(MapMappers.stop(stop), index.toInt()) }

  override fun removeStop(stopId: String, callback: (Result<Boolean>) -> Unit) =
    runJourney(callback) { it.remove(stopId) }

  override fun replaceStop(stop: MapMsgStop, callback: (Result<Boolean>) -> Unit) =
    runJourney(callback) { it.replace(MapMappers.stop(stop)) }

  override fun updateJourney(journey: MapMsgJourney, callback: (Result<Boolean>) -> Unit) =
    runJourney(callback) { it.update(MapMappers.journey(journey)) }

  private fun keep(proposal: JourneyOrderProposal?): MapMsgProposal? {
    proposal ?: return null
    val id = nextProposalId++
    proposals[id] = proposal
    return MapMsgProposal(
      id = id,
      order = proposal.order,
      pinnedStopIds = proposal.pinnedStopIds,
      currentMeters = proposal.currentMeters,
      proposedMeters = proposal.proposedMeters,
      currentSeconds = proposal.currentSeconds,
      proposedSeconds = proposal.proposedSeconds,
    )
  }

  override fun proposeOrder(
    origin: MapMsgOrderOrigin,
    pinnedStopIds: List<String>,
    strategy: MapMsgOrderStrategy,
    callback: (Result<MapMsgProposal?>) -> Unit,
  ) = runJourney(callback) {
    keep(it.proposeOrder(MapMappers.origin(origin), pinnedStopIds.toSet(), MapMappers.strategy(strategy)))
  }

  override fun applyProposal(proposalId: Long, callback: (Result<Boolean>) -> Unit) = runJourney(callback) {
    val proposal = proposals.remove(proposalId)
      ?: throw MapFlutterError("unknownProposal", "The proposal is unknown or was applied.")
    it.apply(proposal)
  }

  override fun resumeJourney(callback: (Result<Unit>) -> Unit) = runJourney(callback) { it.resumeJourney() }

  override fun replanFromHere(pinnedStopIds: List<String>, callback: (Result<MapMsgProposal?>) -> Unit) =
    runJourney(callback) { keep(it.replanFromHere(pinnedStopIds.toSet())) }

  override fun setJourneyRouteOptions(options: MapMsgRouteOptions, callback: (Result<Unit>) -> Unit) =
    runJourney(callback) { it.setRouteOptions(MapMappers.routeOptions(options)) }

  override fun fitActiveLeg(animated: Boolean) = requireNavigator().fitActiveLeg(animated)

  override fun fitJourney(animated: Boolean) = requireNavigator().fitJourney(animated)

  // endregion

  // region Lifecycle

  override fun dispose() {
    if (disposed) return
    disposed = true
    endNavigator()
    session.onFeatureTap = null
    mapView.dismantle()
    session.close()
    scope.cancel()
    MapHostApi.setUp(messenger, null, handle.toString())
  }

  // endregion

  /** Route errors keep the codes and details of flutter_proximiio, so the Dart side reads them alike. */
  private fun flutterError(error: Throwable): MapFlutterError = when (error) {
    is MapFlutterError -> error
    is WayfindingRoutingError -> MapFlutterError("noRoute", error.message, MapMappers.noRouteDetails(error.reason))
    is IllegalArgumentException -> MapFlutterError("invalidArgument", error.message)
    else -> MapFlutterError("underlying", "${error::class.java.simpleName}: ${error.message}")
  }
}
