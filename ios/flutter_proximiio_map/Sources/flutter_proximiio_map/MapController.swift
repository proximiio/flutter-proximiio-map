#if canImport(ProximiioMap)
import Combine
import CoreLocation
import Flutter
import Proximiio
import ProximiioMap
import UIKit

/// Hosts the map view controller and joins it to the nearest parent view controller once the
/// platform view is in a window. The map relies on view-controller containment for its safe-area
/// and appearance callbacks.
final class MapContainerView: UIView {
  let mapController: ProximiioMapViewController

  init(mapController: ProximiioMapViewController) {
    self.mapController = mapController
    super.init(frame: .zero)
    let mapView = mapController.view!
    mapView.frame = bounds
    mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(mapView)
  }

  required init?(coder: NSCoder) { nil }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      guard mapController.parent == nil, let parent = parentViewController() else { return }
      parent.addChild(mapController)
      mapController.didMove(toParent: parent)
    } else if mapController.parent != nil {
      mapController.willMove(toParent: nil)
      mapController.removeFromParent()
    }
  }

  private func parentViewController() -> UIViewController? {
    var responder: UIResponder? = superview
    while let current = responder {
      if let controller = current as? UIViewController { return controller }
      responder = current.next
    }
    return window?.rootViewController
  }
}

/// The map's event channel. On listen it asks the controller for the current state, because the
/// session's publishers emit their first values before Dart listens.
final class MapEventsRelay: MapEventsStreamHandler {
  var sink: PigeonEventSink<MapMsgEvent>?
  var onAttach: (() -> Void)?
  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<MapMsgEvent>) {
    self.sink = sink
    onAttach?()
  }
  override func onCancel(withArguments arguments: Any?) { sink = nil }
}

final class JourneyEventsRelay: JourneyEventsStreamHandler {
  var sink: PigeonEventSink<MapMsgJourneyEvent>?
  var onAttach: (() -> Void)?
  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<MapMsgJourneyEvent>) {
    self.sink = sink
    onAttach?()
  }
  override func onCancel(withArguments arguments: Any?) { sink = nil }
}

/// One map: its view controller, session, published-state subscriptions and journey.
///
/// The map library is main-actor isolated. Flutter and Pigeon call into the plugin on the main
/// thread, so the protocol conformances are `@preconcurrency` (checked at run time).
@MainActor
final class MapController: NSObject {
  private let handle: Int64
  private let messenger: FlutterBinaryMessenger
  private let mapController: ProximiioMapViewController
  private let container: MapContainerView
  private let mapEvents = MapEventsRelay()
  private let journeyEvents = JourneyEventsRelay()
  private var subscriptions = Set<AnyCancellable>()
  private var navigator: JourneyNavigator?
  private var navigatorSubscriptions = Set<AnyCancellable>()
  private var navigatorEventsTask: Task<Void, Never>?
  private var proposals: [Int64: JourneyOrderProposal] = [:]
  private var nextProposalId: Int64 = 1
  private var disposed = false
  private weak var registry: MapRegistry?
  private var journeyStateScheduled = false

  /// The rules the app set; a journey's end clears the session's, so they are put back.
  private var guidanceRules: RouteFollowRules?

  /// Bumped by every route call, so a route that finishes computing after a newer call is not drawn.
  private var routeGeneration = 0

  init(handle: Int64, options: MapOptions, sdk: Proximiio, registry: MapRegistry) {
    self.handle = handle
    self.registry = registry
    messenger = registry.messenger
    mapController = ProximiioMapViewController(sdk: sdk, options: options)
    container = MapContainerView(mapController: mapController)
    super.init()
    let suffix = String(handle)
    MapHostApiSetup.setUp(binaryMessenger: messenger, api: self, messageChannelSuffix: suffix)
    MapEventsStreamHandler.register(with: messenger, instanceName: suffix, streamHandler: mapEvents)
    JourneyEventsStreamHandler.register(with: messenger, instanceName: suffix, streamHandler: journeyEvents)
    mapEvents.onAttach = { [weak self] in MainActor.assumeIsolated { self?.sendSnapshot() } }
    journeyEvents.onAttach = { [weak self] in MainActor.assumeIsolated { self?.sendJourneyState() } }
    observeSession()
  }

  /// The current state, for a listener that attached after the first values.
  private func sendSnapshot() {
    send(MapMsgFloorsChanged(floors: session.floors.map(MapMappers.floor)))
    send(MapMsgSelectedFloorChanged(level: session.selectedFloor.level, isPinned: session.isFloorPinned))
    send(MapMsgCameraModeChanged(mode: MapMappers.cameraMode(session.cameraMode)))
    send(MapMappers.styleSource(session.styleSource))
    send(MapMsgErrorChanged(message: session.lastError))
    send(MapMsgGuidanceChanged(guidance: session.guidance.map {
      MapMappers.guidance($0, text: session.guidanceText.text(for: $0))
    }))
    if session.isCameraReady { send(MapMsgCameraReady(isReady: true)) }
  }


  private var session: ProximiioMapSession { mapController.session }

  private func send(_ event: MapMsgEvent) { mapEvents.sink?.success(event) }

  private func send(_ event: MapMsgJourneyEvent) { journeyEvents.sink?.success(event) }

  /// The session's publishers emit on the main thread; the closures assume that isolation.
  private func observeSession() {
    session.$floors
      .sink { [weak self] floors in
        MainActor.assumeIsolated { self?.send(MapMsgFloorsChanged(floors: floors.map(MapMappers.floor))) }
      }
      .store(in: &subscriptions)
    session.$selectedFloor.combineLatest(session.$isFloorPinned)
      .sink { [weak self] floor, pinned in
        MainActor.assumeIsolated { self?.send(MapMsgSelectedFloorChanged(level: floor.level, isPinned: pinned)) }
      }
      .store(in: &subscriptions)
    session.$cameraMode
      .sink { [weak self] mode in
        MainActor.assumeIsolated { self?.send(MapMsgCameraModeChanged(mode: MapMappers.cameraMode(mode))) }
      }
      .store(in: &subscriptions)
    session.$isCameraReady
      .filter { $0 }
      .first()
      .sink { [weak self] _ in MainActor.assumeIsolated { self?.send(MapMsgCameraReady(isReady: true)) } }
      .store(in: &subscriptions)
    session.$styleSource
      .sink { [weak self] source in MainActor.assumeIsolated { self?.send(MapMappers.styleSource(source)) } }
      .store(in: &subscriptions)
    session.$lastError
      .sink { [weak self] message in MainActor.assumeIsolated { self?.send(MapMsgErrorChanged(message: message)) } }
      .store(in: &subscriptions)
    session.$guidance
      .sink { [weak self] guidance in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.send(MapMsgGuidanceChanged(guidance: guidance.map {
            MapMappers.guidance($0, text: self.session.guidanceText.text(for: $0))
          }))
        }
      }
      .store(in: &subscriptions)
    session.onFeatureTap = { [weak self] ids, coordinate in
      MainActor.assumeIsolated {
        self?.send(MapMsgFeatureTapped(featureIds: ids, coordinate: MapMappers.msg(coordinate)))
      }
    }
  }

  // MARK: Options, camera, floors

  func setOptions(options: MapMsgOptions) throws {
    session.options = MapMappers.options(options)
  }

  func cameraState() throws -> MapMsgCameraState {
    let camera = session.camera
    return MapMsgCameraState(
      center: camera.center.map(MapMappers.msg),
      zoom: camera.zoomLevel,
      direction: camera.direction,
      mode: MapMappers.cameraMode(session.cameraMode)
    )
  }

  func setCenter(center: MapMsgCoordinate, zoom: Double?, animated: Bool) throws {
    if let zoom {
      session.camera.setCenter(MapMappers.coordinate(center), zoom: zoom, animated: animated)
    } else {
      session.camera.setCenter(MapMappers.coordinate(center), animated: animated)
    }
  }

  func setZoom(zoom: Double, animated: Bool) throws { session.camera.setZoom(zoom, animated: animated) }

  func zoomBy(delta: Double, animated: Bool) throws { session.camera.zoom(by: delta, animated: animated) }

  func fitCoordinates(coordinates: [MapMsgCoordinate], animated: Bool) throws {
    session.camera.fit(coordinates: coordinates.map(MapMappers.coordinate), animated: animated)
  }

  func setHeading(degrees: Double?) throws {
    session.setHeading(degrees.map { HeadingAim(degrees: $0) })
  }

  func recentre(zoom: Double?, withHeading: Bool?) throws {
    session.recentre(zoom: zoom, withHeading: withHeading)
  }

  func showVenue(animated: Bool) throws { session.showVenue(animated: animated) }

  func floors() throws -> [MapMsgFloor] { session.floors.map(MapMappers.floor) }

  func selectedFloor() throws -> Double { session.selectedFloor.level }

  func selectFloor(level: Double) throws { session.select(floor: FloorKey(level: level)) }

  func followMyFloor() throws { session.followMyFloor() }

  func setHiddenFeatureIds(ids: [String]) throws { session.hiddenFeatureIDs = Set(ids) }

  func clearTrail() throws { session.clearTrail() }

  // MARK: Routes and guidance

  func showRoute(
    from: MapMsgCoordinate,
    fromLevel: Double,
    to: MapMsgCoordinate,
    toLevel: Double,
    options: MapMsgRouteOptions,
    completion: @escaping (Result<MapMsgRoute, Error>) -> Void
  ) {
    let sdk = session.sdk
    routeGeneration += 1
    let generation = routeGeneration
    Task { @MainActor in
      do {
        let route = try await sdk.computeRoute(
          from: ProximiioCoordinate(latitude: from.latitude, longitude: from.longitude),
          fromLevel: fromLevel,
          to: ProximiioCoordinate(latitude: to.latitude, longitude: to.longitude),
          toLevel: toLevel,
          options: MapMappers.routeOptions(options)
        )
        guard generation == self.routeGeneration, !self.disposed else {
          throw MapFlutterError(
            code: self.disposed ? "notReady" : "superseded",
            message: self.disposed
              ? "The map was disposed."
              : "A later showRoute, clearRoute or startJourney replaced this route.",
            details: nil
          )
        }
        self.session.setRoute(route)
        completion(.success(MapMappers.route(route)))
      } catch {
        completion(.failure(Self.flutterError(error)))
      }
    }
  }

  func clearRoute() throws {
    routeGeneration += 1
    session.clearRoute()
  }

  func setGuidanceRules(rules: MapMsgFollowRules?) throws {
    guidanceRules = rules.map(MapMappers.followRules)
    session.guidanceRules = guidanceRules
  }

  func instructionText(destinationTitle: String?) throws -> String? {
    session.instructionText(destinationTitle: destinationTitle)
  }

  // MARK: Journey

  private func requireNavigator() throws -> JourneyNavigator {
    guard let navigator else { throw MapFlutterError(code: "noJourney", message: "No journey is running.", details: nil) }
    return navigator
  }

  private func runJourney<Value>(
    _ completion: @escaping (Result<Value, Error>) -> Void,
    _ body: @escaping @MainActor (JourneyNavigator) async throws -> Value
  ) {
    Task { @MainActor in
      do {
        completion(.success(try await body(try self.requireNavigator())))
      } catch {
        completion(.failure(Self.flutterError(error)))
      }
    }
  }

  func startJourney(
    journey: MapMsgJourney,
    rules: MapMsgJourneyRules,
    routeOptions: MapMsgRouteOptions,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    endNavigator()
    // The journey draws its own legs; a route still computing must not replace them.
    routeGeneration += 1
    let navigator = JourneyNavigator(
      session: session,
      journey: MapMappers.journey(journey),
      rules: MapMappers.rules(rules),
      guidanceRules: guidanceRules ?? .venueWalk
    )
    self.navigator = navigator
    observe(navigator)
    Task { @MainActor in
      await navigator.setRouteOptions(MapMappers.routeOptions(routeOptions))
      await navigator.start()
      completion(.success(()))
    }
  }

  private func observe(_ navigator: JourneyNavigator) {
    let publishers: [AnyPublisher<Void, Never>] = [
      navigator.$journey.map { _ in () }.eraseToAnyPublisher(),
      navigator.$overview.map { _ in () }.eraseToAnyPublisher(),
      navigator.$deviation.map { _ in () }.eraseToAnyPublisher(),
      navigator.$noRouteReasons.map { _ in () }.eraseToAnyPublisher(),
    ]
    // @Published emits in willSet, before the navigator holds the new value, and one change sets
    // several properties. The state is read once all of them are set, on the next main-queue turn.
    Publishers.MergeMany(publishers)
      .sink { [weak self] in MainActor.assumeIsolated { self?.scheduleJourneyState() } }
      .store(in: &navigatorSubscriptions)
    navigator.$guidance
      .sink { [weak self] guidance in
        MainActor.assumeIsolated {
          guard let self else { return }
          let message = guidance.map {
            MapMsgJourneyGuidance(guidance: MapMappers.guidance($0, text: self.session.guidanceText.text(for: $0)))
          }
          self.send(MapMsgJourneyGuidanceChanged(guidance: message))
        }
      }
      .store(in: &navigatorSubscriptions)
    navigator.onCue = { [weak self] cue in
      self?.send(MapMsgJourneyCue(kind: cue.kind.rawValue, text: cue.text, distanceMeters: cue.distanceMeters))
    }
    let events = navigator.events
    navigatorEventsTask = Task { @MainActor [weak self] in
      for await event in events {
        self?.send(MapMappers.notice(event))
      }
    }
  }

  private func state(of navigator: JourneyNavigator) -> MapMsgJourneyState {
    MapMsgJourneyState(
      journey: MapMappers.msg(navigator.journey),
      overview: MapMappers.overview(navigator.overview),
      deviation: navigator.deviation.map(MapMappers.deviation),
      activeStopId: navigator.activeStop?.id,
      detourStopId: navigator.detourStop?.id,
      hasArrived: navigator.hasArrived,
      isFinished: navigator.isFinished,
      noRouteStopIds: navigator.noRouteReasons.mapValues { MapMappers.caseName($0) },
      reorderableStopIds: navigator.reorderableStops.map(\.id)
    )
  }

  private func sendJourneyState() {
    guard let navigator else { return }
    send(MapMsgJourneyStateChanged(state: state(of: navigator)))
  }

  private func scheduleJourneyState() {
    guard !journeyStateScheduled else { return }
    journeyStateScheduled = true
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.journeyStateScheduled = false
        self.sendJourneyState()
      }
    }
  }

  private func endNavigator() {
    if let navigator {
      navigator.end()
      navigator.onCue = nil
      // end() clears the session's rules; the app's rules apply to routes again.
      session.guidanceRules = guidanceRules
    }
    navigator = nil
    navigatorSubscriptions.removeAll()
    navigatorEventsTask?.cancel()
    navigatorEventsTask = nil
    proposals.removeAll()
  }

  func endJourney() throws { endNavigator() }

  func journeyState() throws -> MapMsgJourneyState? { navigator.map(state(of:)) }

  func advance(completion: @escaping (Result<Void, Error>) -> Void) {
    runJourney(completion) { await $0.advance() }
  }

  func skip(completion: @escaping (Result<Void, Error>) -> Void) {
    runJourney(completion) { await $0.skip() }
  }

  func skipStop(stopId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    runJourney(completion) { await $0.skip(stopID: stopId) }
  }

  func markDone(stopId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    runJourney(completion) { await $0.markDone(stopID: stopId) }
  }

  func reopen(stopId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    runJourney(completion) { await $0.reopen(stopID: stopId) }
  }

  func activate(stopId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    runJourney(completion) { await $0.activate(stopID: stopId) }
  }

  func detour(stop: MapMsgStop, completion: @escaping (Result<Void, Error>) -> Void) {
    runJourney(completion) { await $0.detour(to: MapMappers.stop(stop)) }
  }

  func cancelDetour(completion: @escaping (Result<Void, Error>) -> Void) {
    runJourney(completion) { await $0.cancelDetour() }
  }

  func moveStop(stopId: String, toIndex: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    runJourney(completion) { await $0.move(stopID: stopId, toIndex: Int(toIndex)) }
  }

  func addStop(stop: MapMsgStop, completion: @escaping (Result<Bool, Error>) -> Void) {
    runJourney(completion) { await $0.add(MapMappers.stop(stop)) }
  }

  func insertStop(stop: MapMsgStop, index: Int64, completion: @escaping (Result<Bool, Error>) -> Void) {
    runJourney(completion) { await $0.insert(MapMappers.stop(stop), at: Int(index)) }
  }

  func removeStop(stopId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    runJourney(completion) { await $0.remove(stopID: stopId) }
  }

  func replaceStop(stop: MapMsgStop, completion: @escaping (Result<Bool, Error>) -> Void) {
    runJourney(completion) { await $0.replace(MapMappers.stop(stop)) }
  }

  func updateJourney(journey: MapMsgJourney, completion: @escaping (Result<Bool, Error>) -> Void) {
    runJourney(completion) { await $0.update(to: MapMappers.journey(journey)) }
  }

  /// A proposal Dart can apply by id; one already applied (`applicable` false) is not kept.
  private func keep(_ proposal: JourneyOrderProposal?, applicable: Bool = true) -> MapMsgProposal? {
    guard let proposal else { return nil }
    let id = nextProposalId
    nextProposalId += 1
    if applicable { proposals[id] = proposal }
    return MapMsgProposal(
      id: id,
      order: proposal.order,
      pinnedStopIds: proposal.pinnedStopIDs,
      currentMeters: proposal.currentMeters,
      proposedMeters: proposal.proposedMeters,
      currentSeconds: proposal.currentSeconds,
      proposedSeconds: proposal.proposedSeconds
    )
  }

  func proposeOrder(
    origin: MapMsgOrderOrigin,
    pinnedStopIds: [String],
    strategy: MapMsgOrderStrategy,
    completion: @escaping (Result<MapMsgProposal?, Error>) -> Void
  ) {
    runJourney(completion) { navigator in
      self.keep(
        await navigator.proposeOrder(
          from: MapMappers.origin(origin),
          pinning: Set(pinnedStopIds),
          strategy: MapMappers.strategy(strategy)
        )
      )
    }
  }

  func applyProposal(proposalId: Int64, completion: @escaping (Result<Bool, Error>) -> Void) {
    runJourney(completion) { navigator in
      guard let proposal = self.proposals[proposalId] else {
        throw MapFlutterError(code: "unknownProposal", message: "The proposal is unknown or was applied.", details: nil)
      }
      self.proposals[proposalId] = nil
      return await navigator.apply(proposal)
    }
  }

  func resumeJourney(completion: @escaping (Result<Void, Error>) -> Void) {
    runJourney(completion) { await $0.resumeJourney() }
  }

  func replanFromHere(pinnedStopIds: [String], completion: @escaping (Result<MapMsgProposal?, Error>) -> Void) {
    runJourney(completion) { navigator in
      self.keep(await navigator.replanFromHere(pinning: Set(pinnedStopIds)), applicable: false)
    }
  }

  func setJourneyRouteOptions(options: MapMsgRouteOptions, completion: @escaping (Result<Void, Error>) -> Void) {
    runJourney(completion) { await $0.setRouteOptions(MapMappers.routeOptions(options)) }
  }

  func journeyRouteNetworkChanged(completion: @escaping (Result<Void, Error>) -> Void) {
    runJourney(completion) { await $0.routeNetworkChanged() }
  }

  func fitActiveLeg(animated: Bool) throws { try requireNavigator().fitActiveLeg(animated: animated) }

  func fitJourney(animated: Bool) throws { try requireNavigator().fitJourney(animated: animated) }

  // MARK: Lifecycle

  /// The SDK streams finish at `stop()`; after a restart of the same instance the session takes them again.
  func restartSession() throws {
    guard MainActor.assumeIsolated({ Proximiio.shared }) === session.sdk else {
      throw MapFlutterError(
        code: "notConfigured",
        message: "Proximiio.create replaced the SDK instance this map shows; rebuild the map.",
        details: nil
      )
    }
    session.start()
  }

  func dispose() throws {
    releaseMap()
  }

  func releaseMap() {
    guard !disposed else { return }
    disposed = true
    endNavigator()
    subscriptions.removeAll()
    session.onFeatureTap = nil
    mapEvents.onAttach = nil
    journeyEvents.onAttach = nil
    mapController.dismantle()
    if mapController.parent != nil {
      mapController.willMove(toParent: nil)
      mapController.removeFromParent()
    }
    MapChannels.release(messenger: messenger, handle: handle)
    registry?.removed(handle)
  }

  // MARK: Errors

  /// Route errors keep the codes and details of flutter_proximiio, so the Dart side reads them alike.
  static func flutterError(_ error: Error) -> MapFlutterError {
    if let error = error as? MapFlutterError { return error }
    if let routing = error as? WayfindingRoutingError, case .noRoute(let reason) = routing {
      var details = ["reason": MapMappers.caseName(reason)]
      switch reason {
      case .startOffNetwork(let distance), .goalOffNetwork(let distance):
        details["nearestDistanceMeters"] = String(distance)
      case .noAccessibleRoute(let blockedBy):
        details["blockedBy"] = blockedBy.map { String(describing: $0) }.joined(separator: ",")
      default:
        break
      }
      return MapFlutterError(code: "noRoute", message: String(describing: error), details: details)
    }
    return MapFlutterError(code: "underlying", message: error.localizedDescription, details: nil)
  }
}

extension MapController: @preconcurrency FlutterPlatformView {
  func view() -> UIView { container }
}

extension MapController: @preconcurrency MapHostApi {}

extension MapController: @preconcurrency ReleasableMap {}
#endif
