package io.proximi.flutter_proximiio_map

import io.proximi.map.core.FloorKey
import io.proximi.map.core.GeofenceStyle
import io.proximi.map.core.Journey
import io.proximi.map.core.JourneyDeviation
import io.proximi.map.core.JourneyEvent
import io.proximi.map.core.JourneyOrderOrigin
import io.proximi.map.core.JourneyOrderStrategy
import io.proximi.map.core.JourneyOverview
import io.proximi.map.core.JourneyRules
import io.proximi.map.core.JourneyStop
import io.proximi.map.core.MapColor
import io.proximi.map.core.MapCoordinate
import io.proximi.map.core.MapLayerToggles
import io.proximi.map.core.PositionStyle
import io.proximi.map.core.RouteFollowRules
import io.proximi.map.core.RouteGuidance
import io.proximi.map.core.RouteLineStyle
import io.proximi.map.core.RouteManoeuvre
import io.proximi.map.core.RouteMarkerStyle
import io.proximi.map.kit.MapCameraFollow
import io.proximi.map.kit.MapCanvasChrome
import io.proximi.map.live.MapEdgeInsets
import io.proximi.map.live.MapOptions
import io.proximi.map.live.ProximiioMapSession
import io.proximi.sdk.core.model.ProximiioCoordinate
import io.proximi.sdk.wayfinding.ComputedRoute
import io.proximi.sdk.wayfinding.LevelChange
import io.proximi.sdk.wayfinding.NoRouteReason
import io.proximi.sdk.wayfinding.RouteInstruction
import io.proximi.sdk.wayfinding.RouteOptions

/** Converts between the map library's types and the Pigeon transport types (`MapMsg*`). */
internal object MapMappers {

  // region Options

  fun color(argb: Long): MapColor {
    val value = argb.toInt()
    return MapColor.hex(value and 0xFFFFFF, alpha = ((value ushr 24) and 0xFF) / 255.0)
  }

  private fun edgeInsets(value: MapMsgEdgeInsets) =
    MapEdgeInsets(top = value.top, leading = value.leading, bottom = value.bottom, trailing = value.trailing)

  private fun toggles(value: MapMsgLayerToggles) = MapLayerToggles(
    paths = value.paths,
    walls = value.walls,
    shops = value.shops,
    pois = value.pois,
    amenities = value.amenities,
    baseTiles = value.baseTiles,
  )

  fun options(msg: MapMsgOptions): MapOptions {
    val defaults = MapOptions()
    return MapOptions(
      camera = when (msg.camera) {
        MapMsgCameraMode.FREE -> MapOptions.Camera.FREE
        MapMsgCameraMode.FOLLOW -> MapOptions.Camera.FOLLOW
        MapMsgCameraMode.FOLLOW_WITH_HEADING -> MapOptions.Camera.FOLLOW_WITH_HEADING
      },
      floorSelector = when (msg.floorSelector) {
        MapMsgFloorSelector.NONE -> MapOptions.FloorSelector.NONE
        MapMsgFloorSelector.LEADING -> MapOptions.FloorSelector.LEADING
        MapMsgFloorSelector.TRAILING -> MapOptions.FloorSelector.TRAILING
      },
      trail = when (msg.trail) {
        MapMsgTrailKind.OFF -> MapOptions.Trail.Off
        MapMsgTrailKind.LAST_MINUTES -> MapOptions.Trail.LastMinutes(msg.trailValue ?: 1.0)
        MapMsgTrailKind.LAST_FIXES -> MapOptions.Trail.LastFixes((msg.trailValue ?: 30.0).toInt())
      },
      features = when (msg.features) {
        MapMsgFeaturesKind.VENUE_DEFAULTS -> MapOptions.Features.VenueDefaults
        MapMsgFeaturesKind.NONE -> MapOptions.Features.None
        MapMsgFeaturesKind.ONLY -> MapOptions.Features.Only(msg.layerToggles?.let(::toggles) ?: MapLayerToggles.ALL)
      },
      route = if (msg.showsRoute) MapOptions.Route.AUTOMATIC else MapOptions.Route.OFF,
      routeMarkers = msg.routeMarkers?.let {
        RouteMarkerStyle(isVisible = it.isVisible, color = color(it.color), completedColor = color(it.completedColor))
      } ?: RouteMarkerStyle.VENUE,
      geofences = if (msg.showsGeofences) MapOptions.Geofences.AUTOMATIC else MapOptions.Geofences.OFF,
      geofenceStyle = msg.geofenceStyle?.let {
        GeofenceStyle(
          fillColor = color(it.fillColor),
          fillOpacity = it.fillOpacity,
          lineColor = color(it.lineColor),
          lineWidthDp = it.lineWidth,
        )
      } ?: GeofenceStyle.VENUE,
      contentInsets = when (msg.insets) {
        MapMsgInsetsKind.NONE -> MapOptions.ContentInsets.None
        MapMsgInsetsKind.SAFE_AREA -> MapOptions.ContentInsets.SafeArea
        MapMsgInsetsKind.FIXED -> MapOptions.ContentInsets.Fixed(msg.insetValues?.let(::edgeInsets) ?: MapEdgeInsets.ZERO)
        MapMsgInsetsKind.SAFE_AREA_PLUS ->
          MapOptions.ContentInsets.SafeAreaPlus(msg.insetValues?.let(::edgeInsets) ?: MapEdgeInsets.ZERO)
      },
      amenities = msg.amenities,
      position = PositionStyle.VENUE,
      fallbackStyleUrl = msg.fallbackStyleUrl ?: defaults.fallbackStyleUrl,
      recentreZoom = msg.recentreZoom ?: defaults.recentreZoom,
      offlinePackageId = msg.offlinePackageId,
      chrome = msg.chrome?.let {
        MapCanvasChrome(
          showsLogo = it.showsLogo,
          showsCompass = it.showsCompass,
          showsAttribution = it.showsAttribution,
          allowsTilting = it.allowsTilting,
        )
      } ?: defaults.chrome,
      routeLineStyle = msg.routeLineStyle?.let {
        val to = it.toColor
        RouteLineStyle(
          remaining = if (to == null) RouteLineStyle.Paint.Solid(color(it.color))
          else RouteLineStyle.Paint.Gradient(color(it.color), color(to)),
          completedColor = color(it.completedColor),
          widthDp = it.width,
        )
      },
      initialFraming = when (msg.initialFraming) {
        MapMsgInitialFraming.ALL_FEATURES -> MapOptions.InitialFraming.ALL_FEATURES
        MapMsgInitialFraming.LEGACY_FIRST_FLOOR -> MapOptions.InitialFraming.LEGACY_FIRST_FLOOR
      },
      language = msg.language,
      heading = when (msg.heading) {
        MapMsgHeadingMode.COURSE -> MapOptions.Heading.COURSE
        MapMsgHeadingMode.COMPASS -> MapOptions.Heading.COMPASS
        MapMsgHeadingMode.NONE -> MapOptions.Heading.NONE
      },
      // Not opaque keeps the TextureView that Flutter's texture-layer composition needs.
      backgroundColor = msg.backgroundColor?.toInt() ?: defaults.backgroundColor,
    )
  }

  // endregion

  // region Geometry, floors, camera

  fun mapCoordinate(value: MapMsgCoordinate) = MapCoordinate(latitude = value.latitude, longitude = value.longitude)

  fun msg(value: MapCoordinate) = MapMsgCoordinate(latitude = value.latitude, longitude = value.longitude)

  fun msg(value: ProximiioCoordinate) = MapMsgCoordinate(latitude = value.latitude, longitude = value.longitude)

  fun floor(value: ProximiioMapSession.Floor) = MapMsgFloor(level = value.key.level, name = value.name)

  fun cameraMode(value: MapCameraFollow.Mode): MapMsgCameraMode = when (value) {
    MapCameraFollow.Mode.FREE -> MapMsgCameraMode.FREE
    MapCameraFollow.Mode.FOLLOW -> MapMsgCameraMode.FOLLOW
    MapCameraFollow.Mode.FOLLOW_WITH_HEADING -> MapMsgCameraMode.FOLLOW_WITH_HEADING
  }

  fun styleSource(value: ProximiioMapSession.StyleSource): MapMsgStyleSourceChanged = when (value) {
    ProximiioMapSession.StyleSource.Pending -> MapMsgStyleSourceChanged(kind = MapMsgStyleSourceKind.PENDING)
    ProximiioMapSession.StyleSource.Cache -> MapMsgStyleSourceChanged(kind = MapMsgStyleSourceKind.CACHE)
    ProximiioMapSession.StyleSource.Organization -> MapMsgStyleSourceChanged(kind = MapMsgStyleSourceKind.ORGANIZATION)
    is ProximiioMapSession.StyleSource.OfflinePackage ->
      MapMsgStyleSourceChanged(kind = MapMsgStyleSourceKind.OFFLINE_PACKAGE, detail = value.packageId)
    is ProximiioMapSession.StyleSource.Fallback ->
      MapMsgStyleSourceChanged(kind = MapMsgStyleSourceKind.FALLBACK, detail = value.reason)
  }

  // endregion

  // region Routes and guidance

  /** `NARROW_PATHS` → `narrowPaths`, the Dart and iOS names. */
  fun camelName(value: Enum<*>): String =
    value.name.lowercase().split('_').mapIndexed { index, part ->
      if (index == 0) part else part.replaceFirstChar { it.uppercaseChar() }
    }.joinToString("")

  fun routeOptions(value: MapMsgRouteOptions) = RouteOptions(
    profile = RouteOptions.Profile.entries.firstOrNull { camelName(it) == value.profile } ?: RouteOptions.Profile.PEDESTRIAN,
    avoid = RouteOptions.Avoidance.entries.filter { camelName(it) in value.avoid }.toSet(),
  )

  private fun levelChange(value: LevelChange) = MapMsgLevelChange(
    featureType = value.featureType,
    fromLevel = value.fromLevel,
    toLevel = value.toLevel,
    coordinate = msg(value.coordinate),
  )

  /** The object or class name of a sealed case, as the iOS case name (`TurnLeft` → `turnLeft`). */
  /**
   * The case name of a sealed SDK value (`StartOffNetwork` → `startOffNetwork`). Only for SDK types: the
   * SDK's consumer rules keep their names in release builds; the map library's are not kept.
   */
  fun caseName(value: Any): String = value::class.simpleName?.replaceFirstChar { it.lowercaseChar() } ?: "unknown"

  fun route(value: ComputedRoute) = MapMsgRoute(
    coordinates = value.coordinates.map(::msg),
    distanceMeters = value.distanceMeters,
    segments = value.segments.map {
      MapMsgSegment(start = msg(it.start), end = msg(it.end), distanceMeters = it.distanceMeters)
    },
    level = value.level,
    levelChanges = value.levelChanges.map(::levelChange),
    instructions = value.instructions.map { instruction ->
      val kind = instruction.kind
      MapMsgInstruction(
        kind = caseName(kind),
        coordinate = msg(instruction.coordinate),
        distanceMeters = instruction.distanceMeters,
        level = instruction.level,
        durationSeconds = instruction.durationSeconds,
        levelChange = (kind as? RouteInstruction.Kind.LevelChange)?.let { levelChange(it.change) },
      )
    },
    durationSeconds = value.durationSeconds,
  )

  fun followRules(value: MapMsgFollowRules) = RouteFollowRules(
    arrival = value.arrivalRadiusMeters?.let { RouteFollowRules.ArrivalRadius.Fixed(it) }
      ?: RouteFollowRules.ArrivalRadius.VENUE_WALK,
    arrivalDwellSeconds = value.arrivalDwellSeconds,
    offRouteMeters = value.offRouteMeters,
    offRouteFixes = value.offRouteFixes.toInt(),
  )

  /** Spelled out: release builds obfuscate the map library's class names, so `caseName` would send garbage. */
  private fun manoeuvreKind(kind: RouteManoeuvre.Kind): String = when (kind) {
    RouteManoeuvre.Kind.Start -> "start"
    RouteManoeuvre.Kind.ContinueStraight -> "continueStraight"
    RouteManoeuvre.Kind.TurnSlightLeft -> "turnSlightLeft"
    RouteManoeuvre.Kind.TurnLeft -> "turnLeft"
    RouteManoeuvre.Kind.TurnSharpLeft -> "turnSharpLeft"
    RouteManoeuvre.Kind.TurnSlightRight -> "turnSlightRight"
    RouteManoeuvre.Kind.TurnRight -> "turnRight"
    RouteManoeuvre.Kind.TurnSharpRight -> "turnSharpRight"
    is RouteManoeuvre.Kind.LevelChange -> "levelChange"
    RouteManoeuvre.Kind.Arrive -> "arrive"
  }

  private fun manoeuvre(value: RouteManoeuvre): MapMsgManoeuvre {
    val kind = value.kind
    return MapMsgManoeuvre(
      kind = manoeuvreKind(kind),
      coordinate = msg(value.coordinate),
      level = value.floor.level,
      legMeters = value.legMeters,
      levelChange = (kind as? RouteManoeuvre.Kind.LevelChange)?.change?.let {
        MapMsgLevelChange(
          featureType = it.featureType,
          fromLevel = it.fromLevel,
          toLevel = it.toLevel,
          coordinate = msg(it.coordinate),
        )
      },
    )
  }

  fun guidance(value: RouteGuidance, text: String?) = MapMsgGuidance(
    manoeuvre = value.manoeuvre?.let(::manoeuvre),
    nextManoeuvre = value.nextManoeuvre?.let(::manoeuvre),
    distanceToManoeuvreMeters = value.distanceToManoeuvreMeters,
    remainingMeters = value.remainingMeters,
    traveledMeters = value.traveledMeters,
    offRouteMeters = value.offRouteMeters,
    isOffRoute = value.isOffRoute,
    hasArrived = value.hasArrived,
    arrivalProgress = value.arrivalProgress,
    text = text,
  )

  fun noRouteDetails(reason: NoRouteReason): Map<String, String> {
    val details = mutableMapOf("reason" to caseName(reason))
    when (reason) {
      is NoRouteReason.StartOffNetwork -> details["nearestDistanceMeters"] = reason.nearestDistanceMeters.toString()
      is NoRouteReason.GoalOffNetwork -> details["nearestDistanceMeters"] = reason.nearestDistanceMeters.toString()
      is NoRouteReason.NoAccessibleRoute -> details["blockedBy"] = reason.blockedBy.joinToString(",") { camelName(it) }
      else -> Unit
    }
    return details
  }

  // endregion

  // region Journeys

  fun stop(value: MapMsgStop) = JourneyStop(
    id = value.id,
    title = value.title,
    coordinate = mapCoordinate(value.coordinate),
    floor = value.level?.let { FloorKey(it) },
    poiId = value.poiId,
    kind = if (value.kind == MapMsgStopKind.DETOUR) JourneyStop.Kind.DETOUR else JourneyStop.Kind.PLANNED,
    state = when (value.state) {
      MapMsgStopState.PENDING -> JourneyStop.State.PENDING
      MapMsgStopState.ACTIVE -> JourneyStop.State.ACTIVE
      MapMsgStopState.REACHED -> JourneyStop.State.REACHED
      MapMsgStopState.DONE -> JourneyStop.State.DONE
      MapMsgStopState.SKIPPED -> JourneyStop.State.SKIPPED
    },
    group = value.group,
    iconName = value.iconName,
  )

  fun msg(value: JourneyStop) = MapMsgStop(
    id = value.id,
    title = value.title,
    coordinate = msg(value.coordinate),
    level = value.floor?.level,
    poiId = value.poiId,
    group = value.group,
    iconName = value.iconName,
    kind = if (value.kind == JourneyStop.Kind.DETOUR) MapMsgStopKind.DETOUR else MapMsgStopKind.PLANNED,
    state = when (value.state) {
      JourneyStop.State.PENDING -> MapMsgStopState.PENDING
      JourneyStop.State.ACTIVE -> MapMsgStopState.ACTIVE
      JourneyStop.State.REACHED -> MapMsgStopState.REACHED
      JourneyStop.State.DONE -> MapMsgStopState.DONE
      JourneyStop.State.SKIPPED -> MapMsgStopState.SKIPPED
    },
  )

  fun journey(value: MapMsgJourney) = Journey(stops = value.stops.map(::stop))

  fun msg(value: Journey) = MapMsgJourney(stops = value.stops.map(::msg))

  fun rules(value: MapMsgJourneyRules) = JourneyRules(
    advance = value.advanceOnDepartureMeters?.let { JourneyRules.Advance.OnDeparture(it) } ?: JourneyRules.Advance.Manual,
    rerouteCooldownSeconds = value.rerouteCooldownSeconds,
    walkingSpeedMetersPerSecond = value.walkingSpeedMetersPerSecond,
  )

  fun overview(value: JourneyOverview) = MapMsgOverview(
    remainingStopIds = value.remainingStops.map { it.id },
    legs = value.legs.map { leg ->
      MapMsgLeg(
        destinationStopId = leg.destinationStopId,
        originStopId = leg.originStopId,
        meters = leg.meters,
        isUnreachable = leg.isUnreachable,
        isActive = leg.isActive,
        durationSeconds = leg.durationSeconds,
      )
    },
    remainingMeters = value.remainingMeters,
    etaSeconds = value.etaSeconds,
    activeLegRemainingMeters = value.activeLegRemainingMeters,
    activeLegEtaSeconds = value.activeLegEtaSeconds,
    unmeasuredLegCount = value.unmeasuredLegCount.toLong(),
    unreachableStopIds = value.unreachableStopIds,
  )

  fun deviation(value: JourneyDeviation) = MapMsgDeviation(
    episode = value.episode.toLong(),
    sinceMs = value.since,
    distanceMeters = value.distanceMeters,
    isOnRouteFloor = value.isOnRouteFloor,
  )

  fun notice(event: JourneyEvent): MapMsgJourneyNotice = when (event) {
    is JourneyEvent.LeftRoute -> MapMsgJourneyNotice(kind = "leftRoute", distanceMeters = event.distance)
    is JourneyEvent.FarFromRoute -> MapMsgJourneyNotice(kind = "farFromRoute", distanceMeters = event.distance)
    is JourneyEvent.OffRouteTooLong -> MapMsgJourneyNotice(kind = "offRouteTooLong", durationSeconds = event.duration)
    JourneyEvent.ReturnedToRoute -> MapMsgJourneyNotice(kind = "returnedToRoute")
    is JourneyEvent.DetourOverstayed ->
      MapMsgJourneyNotice(kind = "detourOverstayed", stop = msg(event.stop), durationSeconds = event.duration)
    is JourneyEvent.DetourStarted -> MapMsgJourneyNotice(kind = "detourStarted", stop = msg(event.stop))
    is JourneyEvent.DetourEnded ->
      MapMsgJourneyNotice(kind = "detourEnded", stop = msg(event.stop), completed = event.completed)
    is JourneyEvent.StopReached -> MapMsgJourneyNotice(kind = "stopReached", stop = msg(event.stop))
    is JourneyEvent.StopPassed -> MapMsgJourneyNotice(kind = "stopPassed", stop = msg(event.stop))
    is JourneyEvent.StopSkipped -> MapMsgJourneyNotice(kind = "stopSkipped", stop = msg(event.stop))
    is JourneyEvent.LegChanged ->
      MapMsgJourneyNotice(kind = "legChanged", stop = msg(event.to), reason = camelName(event.reason))
    is JourneyEvent.Rerouted -> MapMsgJourneyNotice(kind = "rerouted", stop = msg(event.to))
    JourneyEvent.JourneyFinished -> MapMsgJourneyNotice(kind = "journeyFinished")
  }

  fun origin(value: MapMsgOrderOrigin): JourneyOrderOrigin =
    if (value == MapMsgOrderOrigin.VISITOR) JourneyOrderOrigin.VISITOR else JourneyOrderOrigin.ACTIVE_STOP

  fun strategy(value: MapMsgOrderStrategy): JourneyOrderStrategy =
    if (value == MapMsgOrderStrategy.FLOOR_THEN_GALLERY) JourneyOrderStrategy.FLOOR_THEN_GALLERY
    else JourneyOrderStrategy.QUICKEST_WALK

  // endregion
}
