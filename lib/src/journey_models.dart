import 'package:flutter_proximiio/flutter_proximiio.dart';

import 'value.dart';

/// Whether a stop belongs to the plan or is a detour.
enum JourneyStopKind {
  /// Part of the planned journey.
  planned,

  /// A detour inserted on the way.
  detour,
}

/// Progress of a stop.
enum JourneyStopState {
  /// Not visited yet.
  pending,

  /// The current destination.
  active,

  /// The visitor is there.
  reached,

  /// Visited.
  done,

  /// Skipped.
  skipped,
}

/// One stop of a [Journey].
class JourneyStop with ValueEquality {
  /// Creates a stop.
  const JourneyStop({
    required this.id,
    required this.title,
    required this.coordinate,
    this.level,
    this.poiId,
    this.group,
    this.iconName,
    this.kind = JourneyStopKind.planned,
    this.state = JourneyStopState.pending,
  });

  /// Decodes a stop written by [toJson].
  factory JourneyStop.fromJson(Map<String, Object?> json) => JourneyStop(
    id: json['id']! as String,
    title: json['title']! as String,
    coordinate: Coordinate(
      latitude: (json['latitude']! as num).toDouble(),
      longitude: (json['longitude']! as num).toDouble(),
    ),
    level: (json['level'] as num?)?.toDouble(),
    poiId: json['poiId'] as String?,
    group: json['group'] as String?,
    iconName: json['iconName'] as String?,
    kind: JourneyStopKind.values.asNameMap()[json['kind']] ?? JourneyStopKind.planned,
    state: JourneyStopState.values.asNameMap()[json['state']] ?? JourneyStopState.pending,
  );

  /// Unique within the journey.
  final String id;

  /// Shown on the map and in your UI.
  final String title;

  /// Position.
  final Coordinate coordinate;

  /// Floor level; `null` for an outdoor stop.
  final double? level;

  /// Id of the POI feature, when the stop is one.
  final String? poiId;

  /// A group name, for apps that list stops by group.
  final String? group;

  /// An icon name for your UI.
  final String? iconName;

  /// Planned or detour.
  final JourneyStopKind kind;

  /// Progress.
  final JourneyStopState state;

  /// A JSON-compatible map, for storing a journey.
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'latitude': coordinate.latitude,
    'longitude': coordinate.longitude,
    if (level != null) 'level': level,
    if (poiId != null) 'poiId': poiId,
    if (group != null) 'group': group,
    if (iconName != null) 'iconName': iconName,
    'kind': kind.name,
    'state': state.name,
  };

  @override
  List<Object?> get props => [id, title, coordinate, level, poiId, group, iconName, kind, state];

  @override
  String toString() => 'JourneyStop($id, $title, ${state.name})';
}

/// A multi-stop journey for [JourneyNavigator].
class Journey with ValueEquality {
  /// Creates a journey.
  const Journey(this.stops);

  /// Decodes a journey written by [toJson].
  factory Journey.fromJson(Map<String, Object?> json) => Journey([
    for (final stop in json['stops']! as List<Object?>) JourneyStop.fromJson(stop! as Map<String, Object?>),
  ]);

  /// The stops of a journey edited in Proximi.io Portal. Waypoints without a position are
  /// left out; stop ids are `<journey id>-<index>`.
  factory Journey.fromProximiioJourney(ProximiioJourney journey) => Journey([
    for (final (index, waypoint) in journey.waypoints.indexed)
      if (waypoint.latitude != null && waypoint.longitude != null)
        JourneyStop(
          id: '${journey.id ?? 'journey'}-$index',
          title: waypoint.label ?? 'Stop ${index + 1}',
          coordinate: Coordinate(latitude: waypoint.latitude!, longitude: waypoint.longitude!),
          level: waypoint.level,
        ),
  ]);

  /// The stops, in visiting order.
  final List<JourneyStop> stops;

  /// A JSON-compatible map, for storing a journey.
  Map<String, Object?> toJson() => {
    'stops': [for (final stop in stops) stop.toJson()],
  };

  @override
  List<Object?> get props => [stops];
}

/// When the navigator moves on to the next stop.
class JourneyRules with ValueEquality {
  /// Creates rules; the defaults are the native `venueVisit` preset.
  const JourneyRules({
    this.advanceOnDepartureMeters,
    this.rerouteCooldown = const Duration(seconds: 10),
    this.walkingSpeedMetersPerSecond = 1.2,
  });

  /// The native `venueVisit` preset: advance manually.
  static const venueVisit = JourneyRules();

  /// Advance after walking this far from a reached stop; `null` advances only on [JourneyNavigator.advance].
  final double? advanceOnDepartureMeters;

  /// Minimum time between two automatic reroutes.
  final Duration rerouteCooldown;

  /// Walking speed for the time estimates.
  final double walkingSpeedMetersPerSecond;

  @override
  List<Object?> get props => [advanceOnDepartureMeters, rerouteCooldown, walkingSpeedMetersPerSecond];
}

/// One leg of the journey, to a stop.
class JourneyLeg with ValueEquality {
  /// Creates a leg.
  const JourneyLeg({
    required this.destinationStopId,
    required this.isActive,
    required this.isUnreachable,
    this.originStopId,
    this.meters,
    this.duration,
  });

  /// The stop the leg leads to.
  final String destinationStopId;

  /// The stop it starts from; `null` for the first leg from the visitor.
  final String? originStopId;

  /// Walking distance; `null` while not measured or when unreachable.
  final double? meters;

  /// No route leads to the destination.
  final bool isUnreachable;

  /// The leg being walked.
  final bool isActive;

  /// Estimated time.
  final Duration? duration;

  @override
  List<Object?> get props => [destinationStopId, originStopId, meters, isUnreachable, isActive, duration];
}

/// Distances and times of the rest of the journey.
class JourneyOverview with ValueEquality {
  /// Creates an overview.
  const JourneyOverview({
    required this.remainingStopIds,
    required this.legs,
    required this.remainingMeters,
    required this.eta,
    required this.unmeasuredLegCount,
    required this.unreachableStopIds,
    this.activeLegRemainingMeters,
    this.activeLegEta,
  });

  /// Stops still ahead.
  final List<String> remainingStopIds;

  /// Legs still ahead.
  final List<JourneyLeg> legs;

  /// Walking distance left.
  final double remainingMeters;

  /// Time left.
  final Duration eta;

  /// Distance left on the active leg.
  final double? activeLegRemainingMeters;

  /// Time left on the active leg.
  final Duration? activeLegEta;

  /// Legs not measured yet.
  final int unmeasuredLegCount;

  /// Stops no route leads to.
  final List<String> unreachableStopIds;

  @override
  List<Object?> get props => [
    remainingStopIds,
    legs,
    remainingMeters,
    eta,
    activeLegRemainingMeters,
    activeLegEta,
    unmeasuredLegCount,
    unreachableStopIds,
  ];
}

/// The visitor is off the journey's route.
class JourneyDeviation with ValueEquality {
  /// Creates a deviation.
  const JourneyDeviation({
    required this.episode,
    required this.since,
    required this.distanceMeters,
    required this.isOnRouteFloor,
  });

  /// Counts deviations within the journey.
  final int episode;

  /// When the visitor left the route.
  final DateTime since;

  /// Distance from the route.
  final double distanceMeters;

  /// Whether the visitor is on the floor of the route.
  final bool isOnRouteFloor;

  @override
  List<Object?> get props => [episode, since, distanceMeters, isOnRouteFloor];
}

/// The navigator's state.
class JourneyState with ValueEquality {
  /// Creates a state.
  const JourneyState({
    required this.journey,
    required this.overview,
    required this.hasArrived,
    required this.isFinished,
    required this.noRouteReasons,
    this.reorderableStopIds = const [],
    this.deviation,
    this.activeStopId,
    this.detourStopId,
  });

  /// The journey with its stop states.
  final Journey journey;

  /// Distances and times ahead.
  final JourneyOverview overview;

  /// Set while the visitor is off the route.
  final JourneyDeviation? deviation;

  /// The current destination.
  final String? activeStopId;

  /// The detour being walked.
  final String? detourStopId;

  /// The visitor is at the active stop.
  final bool hasArrived;

  /// Every stop is done or skipped.
  final bool isFinished;

  /// Stops no route leads to, with the reason (`null` for a reason added after this release).
  final Map<String, NoRouteReason?> noRouteReasons;

  /// Ids of [reorderableStops].
  final List<String> reorderableStopIds;

  /// The stops a reorder may touch, in walking order: the stops still to walk except one already
  /// reached and a live detour. [JourneyNavigator.moveStop] and [JourneyNavigator.insertStop] take an
  /// index into this list, not into `journey.stops`.
  List<JourneyStop> get reorderableStops {
    final byId = {for (final stop in journey.stops) stop.id: stop};
    return [for (final id in reorderableStopIds) ?byId[id]];
  }

  /// The active stop.
  JourneyStop? get activeStop => journey.stops.where((s) => s.id == activeStopId).firstOrNull;

  @override
  List<Object?> get props => [
    journey,
    overview,
    deviation,
    activeStopId,
    detourStopId,
    reorderableStopIds,
    hasArrived,
    isFinished,
    noRouteReasons,
  ];
}

/// Something that happened during the journey.
sealed class JourneyEvent with ValueEquality {
  const JourneyEvent();
}

/// The visitor left the route.
final class JourneyLeftRoute extends JourneyEvent {
  /// Creates the event.
  const JourneyLeftRoute(this.distanceMeters);

  /// Distance from the route.
  final double distanceMeters;

  @override
  List<Object?> get props => [distanceMeters];
}

/// The visitor is far from the route.
final class JourneyFarFromRoute extends JourneyEvent {
  /// Creates the event.
  const JourneyFarFromRoute(this.distanceMeters);

  /// Distance from the route.
  final double distanceMeters;

  @override
  List<Object?> get props => [distanceMeters];
}

/// The visitor has been off the route for long.
final class JourneyOffRouteTooLong extends JourneyEvent {
  /// Creates the event.
  const JourneyOffRouteTooLong(this.duration);

  /// Time off the route.
  final Duration duration;

  @override
  List<Object?> get props => [duration];
}

/// The visitor is back on the route.
final class JourneyReturnedToRoute extends JourneyEvent {
  /// Creates the event.
  const JourneyReturnedToRoute();

  @override
  List<Object?> get props => const [];
}

/// The visitor stays at a detour longer than expected.
final class JourneyDetourOverstayed extends JourneyEvent {
  /// Creates the event.
  const JourneyDetourOverstayed(this.stop, this.duration);

  /// The detour.
  final JourneyStop stop;

  /// Time at the detour.
  final Duration duration;

  @override
  List<Object?> get props => [stop, duration];
}

/// A detour started.
final class JourneyDetourStarted extends JourneyEvent {
  /// Creates the event.
  const JourneyDetourStarted(this.stop);

  /// The detour.
  final JourneyStop stop;

  @override
  List<Object?> get props => [stop];
}

/// A detour ended.
final class JourneyDetourEnded extends JourneyEvent {
  /// Creates the event.
  const JourneyDetourEnded(this.stop, {required this.completed});

  /// The detour.
  final JourneyStop stop;

  /// Whether the visitor reached it.
  final bool completed;

  @override
  List<Object?> get props => [stop, completed];
}

/// The visitor reached a stop.
final class JourneyStopReached extends JourneyEvent {
  /// Creates the event.
  const JourneyStopReached(this.stop);

  /// The stop.
  final JourneyStop stop;

  @override
  List<Object?> get props => [stop];
}

/// The visitor walked past a stop.
final class JourneyStopPassed extends JourneyEvent {
  /// Creates the event.
  const JourneyStopPassed(this.stop);

  /// The stop.
  final JourneyStop stop;

  @override
  List<Object?> get props => [stop];
}

/// A stop was skipped.
final class JourneyStopSkipped extends JourneyEvent {
  /// Creates the event.
  const JourneyStopSkipped(this.stop);

  /// The stop.
  final JourneyStop stop;

  @override
  List<Object?> get props => [stop];
}

/// The active leg changed.
final class JourneyLegChanged extends JourneyEvent {
  /// Creates the event.
  const JourneyLegChanged(this.stop, {required this.reason});

  /// The new destination.
  final JourneyStop stop;

  /// Why: `started`, `advanced`, `skipped`, `detour`, `detourCancelled`, `resumed`, `reordered`, …
  final String reason;

  @override
  List<Object?> get props => [stop, reason];
}

/// The leg was routed again.
final class JourneyRerouted extends JourneyEvent {
  /// Creates the event.
  const JourneyRerouted(this.stop);

  /// The destination.
  final JourneyStop stop;

  @override
  List<Object?> get props => [stop];
}

/// The journey is finished.
final class JourneyFinished extends JourneyEvent {
  /// Creates the event.
  const JourneyFinished();

  @override
  List<Object?> get props => const [];
}

/// An event added after this plugin release.
final class JourneyUnknownEvent extends JourneyEvent {
  /// Creates the event.
  const JourneyUnknownEvent(this.kind);

  /// The native case name.
  final String kind;

  @override
  List<Object?> get props => [kind];
}

/// What a cue announces.
enum JourneyCueKind {
  /// A turn or the start.
  manoeuvre,

  /// A floor change.
  levelChange,

  /// The destination is near.
  approachingDestination,

  /// Arrived.
  arrived,

  /// A kind added after this plugin release.
  unknown,
}

/// A spoken-style announcement, for text-to-speech.
class JourneyCue with ValueEquality {
  /// Creates a cue.
  const JourneyCue({required this.kind, required this.text, required this.distanceMeters});

  /// What it announces.
  final JourneyCueKind kind;

  /// The announcement, in the map's language.
  final String text;

  /// Distance to the announced point.
  final double distanceMeters;

  @override
  List<Object?> get props => [kind, text, distanceMeters];
}

/// Where a reordering starts from.
enum JourneyOrderOrigin {
  /// The active stop.
  activeStop,

  /// The visitor's position.
  visitor,
}

/// How a reordering orders the stops.
enum JourneyOrderStrategy {
  /// The shortest walk.
  quickestWalk,

  /// Floor by floor, then by gallery.
  floorThenGallery,
}

/// A proposed stop order from [JourneyNavigator.proposeOrder]. Apply it with [JourneyNavigator.apply].
class JourneyOrderProposal with ValueEquality {
  /// Creates a proposal. Internal: proposals come from the navigator.
  const JourneyOrderProposal({
    required this.id,
    required this.order,
    required this.pinnedStopIds,
    required this.currentMeters,
    required this.proposedMeters,
    required this.currentDuration,
    required this.proposedDuration,
  });

  /// Identifies the proposal on the native side.
  final int id;

  /// The proposed stop order.
  final List<String> order;

  /// Stops that keep their place.
  final List<String> pinnedStopIds;

  /// Walking distance of the current order.
  final double currentMeters;

  /// Walking distance of the proposed order.
  final double proposedMeters;

  /// Time of the current order.
  final Duration currentDuration;

  /// Time of the proposed order.
  final Duration proposedDuration;

  /// Metres saved.
  double get savedMeters => (currentMeters - proposedMeters).clamp(0, double.infinity);

  @override
  List<Object?> get props => [
    id,
    order,
    pinnedStopIds,
    currentMeters,
    proposedMeters,
    currentDuration,
    proposedDuration,
  ];
}
