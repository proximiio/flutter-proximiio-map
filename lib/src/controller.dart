import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_proximiio/flutter_proximiio.dart';

import 'convert.dart';
import 'errors.dart';
import 'guidance.dart';
import 'journey_models.dart';
import 'messages.g.dart' as msg;
import 'options.dart';

/// A floor of the map.
@immutable
class MapFloor {
  /// Creates a floor.
  const MapFloor({required this.level, this.name});

  /// Level.
  final double level;

  /// Name from the venue data.
  final String? name;

  @override
  bool operator ==(Object other) => other is MapFloor && other.level == level && other.name == name;

  @override
  int get hashCode => Object.hash(level, name);

  @override
  String toString() => 'MapFloor($level, $name)';
}

/// The floor the map shows.
@immutable
class MapFloorSelection {
  /// Creates a selection.
  const MapFloorSelection({required this.level, required this.isPinned});

  /// Level shown.
  final double level;

  /// The floor was chosen by the user or the app; the map no longer follows the visitor's floor
  /// until [ProximiioMapController.followMyFloor].
  final bool isPinned;

  @override
  bool operator ==(Object other) => other is MapFloorSelection && other.level == level && other.isPinned == isPinned;

  @override
  int get hashCode => Object.hash(level, isPinned);
}

/// Where the map style came from.
enum MapStyleSource {
  /// Loading.
  pending,

  /// The stored copy.
  cache,

  /// The organisation style from the API.
  organization,

  /// An installed offline package.
  offlinePackage,

  /// The fallback style; the organisation style could not be loaded.
  fallback,
}

/// A tap on venue features.
@immutable
class MapFeatureTap {
  /// Creates a tap.
  const MapFeatureTap({required this.featureIds, required this.coordinate});

  /// Ids of the venue features under the tap; empty for a tap elsewhere.
  final List<String> featureIds;

  /// Where the tap was.
  final Coordinate coordinate;
}

/// The camera's current position.
@immutable
class MapCameraState {
  /// Creates a state.
  const MapCameraState({required this.mode, this.center, this.zoom, this.direction});

  /// Centre of the view.
  final Coordinate? center;

  /// Zoom level.
  final double? zoom;

  /// Bearing in degrees.
  final double? direction;

  /// Camera mode.
  final CameraMode mode;
}

/// Wraps the native map with [handle]. Not exported: the widget creates controllers; tests pass
/// fakes for [api] and [events].
ProximiioMapController createMapController(
  int handle, {
  msg.MapHostApi? api,
  Stream<msg.MapMsgEvent>? events,
  Stream<msg.MapMsgJourneyEvent> Function()? journeyEvents,
}) => ProximiioMapController._(
  api ?? msg.MapHostApi(messageChannelSuffix: '$handle'),
  events ?? msg.mapEvents(instanceName: '$handle'),
  journeyEvents ?? () => msg.journeyEvents(instanceName: '$handle'),
);

/// Controls one [ProximiioMap]. Get it from `ProximiioMap.onMapCreated`.
///
/// State the map changes by itself (floors, camera mode, guidance, errors) is exposed as
/// [ValueListenable]s for `ValueListenableBuilder`.
class ProximiioMapController {
  ProximiioMapController._(this._api, Stream<msg.MapMsgEvent> events, this._journeyEvents) {
    _subscription = events.listen(_onEvent);
  }

  final msg.MapHostApi _api;
  final Stream<msg.MapMsgJourneyEvent> Function() _journeyEvents;
  late final StreamSubscription<msg.MapMsgEvent> _subscription;
  final _featureTaps = StreamController<MapFeatureTap>.broadcast();
  final _cameraReady = Completer<void>();
  JourneyNavigator? _journey;
  bool _disposed = false;

  final ValueNotifier<List<MapFloor>> _floors = ValueNotifier(const []);
  final ValueNotifier<MapFloorSelection> _selectedFloor = ValueNotifier(
    const MapFloorSelection(level: 0, isPinned: false),
  );
  final ValueNotifier<CameraMode> _cameraMode = ValueNotifier(CameraMode.follow);
  final ValueNotifier<MapStyleSource> _styleSource = ValueNotifier(MapStyleSource.pending);
  final ValueNotifier<String?> _lastError = ValueNotifier(null);
  final ValueNotifier<RouteGuidance?> _guidance = ValueNotifier(null);

  /// The floors of the venue.
  ValueListenable<List<MapFloor>> get floors => _floors;

  /// The floor shown.
  ValueListenable<MapFloorSelection> get selectedFloor => _selectedFloor;

  /// The camera mode now; [recentre] returns to following the visitor.
  ValueListenable<CameraMode> get cameraMode => _cameraMode;

  /// Where the style came from.
  ValueListenable<MapStyleSource> get styleSource => _styleSource;

  /// The last error the map reported (style or data loading), for display; `null` when fine.
  ValueListenable<String?> get lastError => _lastError;

  /// Guidance along the route from [showRoute], after [setGuidanceRules].
  ValueListenable<RouteGuidance?> get guidance => _guidance;

  /// Taps on the map.
  Stream<MapFeatureTap> get featureTaps => _featureTaps.stream;

  /// Completes when the camera has framed the venue for the first time.
  Future<void> get cameraReady => _cameraReady.future;

  /// The running journey, if any.
  JourneyNavigator? get journey => _journey;

  void _onEvent(msg.MapMsgEvent event) {
    switch (event) {
      case msg.MapMsgCameraReady():
        if (!_cameraReady.isCompleted) _cameraReady.complete();
      case msg.MapMsgStyleSourceChanged(:final kind):
        _styleSource.value = MapStyleSource.values.byName(kind.name);
      case msg.MapMsgFeatureTapped(:final featureIds, :final coordinate):
        _featureTaps.add(MapFeatureTap(featureIds: featureIds, coordinate: fromMsgCoordinate(coordinate)));
      case msg.MapMsgFloorsChanged(:final floors):
        _floors.value = [for (final f in floors) MapFloor(level: f.level, name: f.name)];
      case msg.MapMsgSelectedFloorChanged(:final level, :final isPinned):
        _selectedFloor.value = MapFloorSelection(level: level, isPinned: isPinned);
      case msg.MapMsgCameraModeChanged(:final mode):
        _cameraMode.value = CameraMode.values.byName(mode.name);
      case msg.MapMsgGuidanceChanged(:final guidance):
        _guidance.value = guidance == null ? null : fromMsgGuidance(guidance);
      case msg.MapMsgErrorChanged(:final message):
        _lastError.value = message;
    }
  }

  Future<T> _call<T>(Future<T> Function() call) {
    if (_disposed) {
      return Future.error(const ProximiioMapException(MapErrorCode.notReady, message: 'The map was disposed.'));
    }
    return guardedMap(call);
  }

  // ── Options and camera ──

  /// Replaces the options.
  Future<void> setOptions(MapOptions options) => _call(() => _api.setOptions(toMsgOptions(options)));

  /// The camera's position now.
  Future<MapCameraState> cameraState() => _call(() async {
    final state = await _api.cameraState();
    return MapCameraState(
      center: state.center == null ? null : fromMsgCoordinate(state.center!),
      zoom: state.zoom,
      direction: state.direction,
      mode: CameraMode.values.byName(state.mode.name),
    );
  });

  /// Moves the camera to [center].
  Future<void> setCenter(Coordinate center, {double? zoom, bool animated = true}) =>
      _call(() => _api.setCenter(toMsgCoordinate(center), zoom, animated));

  /// Sets the zoom.
  Future<void> setZoom(double zoom, {bool animated = true}) => _call(() => _api.setZoom(zoom, animated));

  /// Changes the zoom by [delta].
  Future<void> zoomBy(double delta, {bool animated = true}) => _call(() => _api.zoomBy(delta, animated));

  /// Frames [coordinates].
  Future<void> fitCoordinates(List<Coordinate> coordinates, {bool animated = true}) =>
      _call(() => _api.fitCoordinates([for (final c in coordinates) toMsgCoordinate(c)], animated));

  /// Points the dot to [degrees] (for example from your own sensor fusion); `null` returns to [MapOptions.heading].
  Future<void> setHeading(double? degrees) => _call(() => _api.setHeading(degrees));

  /// Follows the visitor again, at [zoom] (default [MapOptions.recentreZoom]).
  Future<void> recentre({double? zoom, bool? withHeading}) => _call(() => _api.recentre(zoom, withHeading));

  /// Frames the whole venue.
  Future<void> showVenue({bool animated = true}) => _call(() => _api.showVenue(animated));

  // ── Floors and features ──

  /// Shows the floor at [level] and pins it.
  Future<void> selectFloor(double level) => _call(() => _api.selectFloor(level));

  /// Follows the visitor's floor again.
  Future<void> followMyFloor() => _call(_api.followMyFloor);

  /// Hides the features with these ids (for example to replace them with your own markers).
  Future<void> setHiddenFeatureIds(Set<String> ids) => _call(() => _api.setHiddenFeatureIds(ids.toList()));

  /// Clears the trail behind the dot.
  Future<void> clearTrail() => _call(_api.clearTrail);

  // ── Routes and guidance ──

  /// Computes a route with the SDK and shows it. Throws [ProximiioException] with
  /// [ProximiioErrorCode.noRoute] when none exists.
  Future<ComputedRoute> showRoute({
    required Coordinate from,
    required double fromLevel,
    required Coordinate to,
    double? toLevel,
    RouteOptions options = const RouteOptions(),
  }) => _call(
    () async => fromMsgRoute(
      await _api.showRoute(
        toMsgCoordinate(from),
        fromLevel,
        toMsgCoordinate(to),
        toLevel ?? fromLevel,
        toMsgRouteOptions(options),
      ),
    ),
  );

  /// Removes the route.
  Future<void> clearRoute() => _call(_api.clearRoute);

  /// Turns guidance along the shown route on with [rules], or off with `null`. Guidance arrives in [guidance].
  Future<void> setGuidanceRules(RouteFollowRules? rules) =>
      _call(() => _api.setGuidanceRules(rules == null ? null : toMsgFollowRules(rules)));

  /// The current instruction as text (English or Arabic), naming [destinationTitle] on arrival.
  Future<String?> instructionText({String? destinationTitle}) => _call(() => _api.instructionText(destinationTitle));

  // ── Journeys ──

  /// Starts a multi-stop journey on this map, replacing a running one.
  Future<JourneyNavigator> startJourney(
    Journey journey, {
    JourneyRules rules = JourneyRules.venueVisit,
    RouteOptions routeOptions = const RouteOptions(),
  }) => _call(() async {
    await _journey?._close();
    final navigator = JourneyNavigator._(_api, _journeyEvents());
    _journey = navigator;
    await _api.startJourney(toMsgJourney(journey), toMsgJourneyRules(rules), toMsgRouteOptions(routeOptions));
    return navigator;
  });

  /// Releases the map. The widget calls this when it is removed.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _journey?._close();
    await _subscription.cancel();
    await _featureTaps.close();
    for (final notifier in [_floors, _selectedFloor, _cameraMode, _styleSource, _lastError, _guidance]) {
      notifier.dispose();
    }
    try {
      await _api.dispose();
    } on Object {
      // The view may already be gone.
    }
  }
}

/// A running multi-stop journey. Get it from [ProximiioMapController.startJourney].
class JourneyNavigator {
  JourneyNavigator._(this._api, Stream<msg.MapMsgJourneyEvent> events) {
    _subscription = events.listen(_onEvent);
  }

  final msg.MapHostApi _api;
  late final StreamSubscription<msg.MapMsgJourneyEvent> _subscription;
  final ValueNotifier<JourneyState?> _state = ValueNotifier(null);
  final ValueNotifier<RouteGuidance?> _guidance = ValueNotifier(null);
  final _events = StreamController<JourneyEvent>.broadcast();
  final _cues = StreamController<JourneyCue>.broadcast();
  bool _closed = false;

  /// The journey's state: stops, overview, deviation.
  ValueListenable<JourneyState?> get state => _state;

  /// Guidance along the active leg.
  ValueListenable<RouteGuidance?> get guidance => _guidance;

  /// Journey events (stop reached, left route, leg changed, …).
  Stream<JourneyEvent> get events => _events.stream;

  /// Announcements for text-to-speech.
  Stream<JourneyCue> get cues => _cues.stream;

  void _onEvent(msg.MapMsgJourneyEvent event) {
    switch (event) {
      case msg.MapMsgJourneyStateChanged(:final state):
        _state.value = fromMsgJourneyState(state);
      case msg.MapMsgJourneyGuidanceChanged(:final guidance):
        _guidance.value = guidance == null ? null : fromMsgGuidance(guidance.guidance);
      case msg.MapMsgJourneyNotice():
        _events.add(fromMsgNotice(event));
      case msg.MapMsgJourneyCue():
        _cues.add(fromMsgCue(event));
    }
  }

  Future<T> _call<T>(Future<T> Function() call) {
    if (_closed) {
      return Future.error(const ProximiioMapException(MapErrorCode.noJourney, message: 'The journey ended.'));
    }
    return guardedMap(call);
  }

  /// Moves on to the next stop.
  Future<void> advance() => _call(_api.advance);

  /// Skips the active stop.
  Future<void> skip() => _call(_api.skip);

  /// Skips the stop [stopId].
  Future<bool> skipStop(String stopId) => _call(() => _api.skipStop(stopId));

  /// Marks the stop [stopId] as done.
  Future<bool> markDone(String stopId) => _call(() => _api.markDone(stopId));

  /// Makes a done or skipped stop pending again.
  Future<bool> reopen(String stopId) => _call(() => _api.reopen(stopId));

  /// Makes the stop [stopId] the active one.
  Future<bool> activate(String stopId) => _call(() => _api.activate(stopId));

  /// Walks to [stop] first, then resumes the journey.
  Future<void> detour(JourneyStop stop) => _call(() => _api.detour(toMsgStop(stop)));

  /// Cancels the detour.
  Future<void> cancelDetour() => _call(_api.cancelDetour);

  /// Moves the stop [stopId] to [toIndex].
  Future<void> moveStop(String stopId, int toIndex) => _call(() => _api.moveStop(stopId, toIndex));

  /// Adds [stop] at the end.
  Future<bool> addStop(JourneyStop stop) => _call(() => _api.addStop(toMsgStop(stop)));

  /// Inserts [stop] at [index].
  Future<bool> insertStop(JourneyStop stop, int index) => _call(() => _api.insertStop(toMsgStop(stop), index));

  /// Removes the stop [stopId].
  Future<bool> removeStop(String stopId) => _call(() => _api.removeStop(stopId));

  /// Replaces the stop with the same id.
  Future<bool> replaceStop(JourneyStop stop) => _call(() => _api.replaceStop(toMsgStop(stop)));

  /// Replaces the journey, keeping the progress of stops that remain.
  Future<bool> update(Journey journey) => _call(() => _api.updateJourney(toMsgJourney(journey)));

  /// Proposes a quicker order of the remaining stops; `null` when the current order is best.
  Future<JourneyOrderProposal?> proposeOrder({
    JourneyOrderOrigin origin = JourneyOrderOrigin.activeStop,
    Set<String> pinnedStopIds = const {},
    JourneyOrderStrategy strategy = JourneyOrderStrategy.quickestWalk,
  }) => _call(() async {
    final proposal = await _api.proposeOrder(
      msg.MapMsgOrderOrigin.values.byName(origin.name),
      pinnedStopIds.toList(),
      msg.MapMsgOrderStrategy.values.byName(strategy.name),
    );
    return proposal == null ? null : fromMsgProposal(proposal);
  });

  /// Applies a proposal from [proposeOrder] or [replanFromHere]; `false` when it is out of date.
  Future<bool> apply(JourneyOrderProposal proposal) => _call(() => _api.applyProposal(proposal.id));

  /// Resumes after a detour or a deviation.
  Future<void> resumeJourney() => _call(_api.resumeJourney);

  /// Proposes an order from the visitor's position.
  Future<JourneyOrderProposal?> replanFromHere({Set<String> pinnedStopIds = const {}}) => _call(() async {
    final proposal = await _api.replanFromHere(pinnedStopIds.toList());
    return proposal == null ? null : fromMsgProposal(proposal);
  });

  /// Routes the journey with [options] (for example step-free).
  Future<void> setRouteOptions(RouteOptions options) =>
      _call(() => _api.setJourneyRouteOptions(toMsgRouteOptions(options)));

  /// Frames the active leg.
  Future<void> fitActiveLeg({bool animated = true}) => _call(() => _api.fitActiveLeg(animated));

  /// Frames the whole journey.
  Future<void> fitJourney({bool animated = true}) => _call(() => _api.fitJourney(animated));

  /// Ends the journey.
  Future<void> end() async {
    if (_closed) return;
    await guardedMap(_api.endJourney);
    await _close();
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await _events.close();
    await _cues.close();
    _state.dispose();
    _guidance.dispose();
  }
}
