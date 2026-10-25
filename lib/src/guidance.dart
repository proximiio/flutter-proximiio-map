import 'package:flutter_proximiio/flutter_proximiio.dart';

import 'value.dart';

/// How the map follows the visitor along a route.
class RouteFollowRules with ValueEquality {
  /// Creates rules; the defaults are the native `venueWalk` preset.
  const RouteFollowRules({
    this.arrivalRadiusMeters,
    this.arrivalDwell = const Duration(seconds: 2),
    this.offRouteMeters = 12,
    this.offRouteFixes = 3,
  });

  /// The native `venueWalk` preset.
  static const venueWalk = RouteFollowRules();

  /// Fixed arrival radius; `null` derives it from the position accuracy (3 to 10 m).
  final double? arrivalRadiusMeters;

  /// How long the visitor stays within the radius before arrival is reported.
  final Duration arrivalDwell;

  /// Distance from the route that counts as off route.
  final double offRouteMeters;

  /// Positions in a row beyond [offRouteMeters] before off route is reported.
  final int offRouteFixes;

  @override
  List<Object?> get props => [arrivalRadiusMeters, arrivalDwell, offRouteMeters, offRouteFixes];
}

/// What the next manoeuvre asks the visitor to do.
enum ManoeuvreKind {
  /// Start walking.
  start,

  /// Go straight on.
  continueStraight,

  /// Turn slightly left.
  turnSlightLeft,

  /// Turn left.
  turnLeft,

  /// Turn sharply left.
  turnSharpLeft,

  /// Turn slightly right.
  turnSlightRight,

  /// Turn right.
  turnRight,

  /// Turn sharply right.
  turnSharpRight,

  /// Change floor; see [RouteManoeuvre.levelChange].
  levelChange,

  /// Arrive.
  arrive,

  /// A kind added after this plugin release.
  unknown,
}

/// One manoeuvre of the route being followed.
class RouteManoeuvre with ValueEquality {
  /// Creates a manoeuvre.
  const RouteManoeuvre({
    required this.kind,
    required this.coordinate,
    required this.level,
    required this.legMeters,
    this.levelChange,
  });

  /// What to do.
  final ManoeuvreKind kind;

  /// Where.
  final Coordinate coordinate;

  /// Level of the floor.
  final double level;

  /// Length of the leg leading to it, in metres.
  final double legMeters;

  /// The ride, for [ManoeuvreKind.levelChange].
  final LevelChange? levelChange;

  @override
  List<Object?> get props => [kind, coordinate, level, legMeters, levelChange];
}

/// Progress along the route being followed.
class RouteGuidance with ValueEquality {
  /// Creates guidance.
  const RouteGuidance({
    required this.distanceToManoeuvreMeters,
    required this.remainingMeters,
    required this.traveledMeters,
    required this.offRouteMeters,
    required this.isOffRoute,
    required this.hasArrived,
    required this.arrivalProgress,
    this.manoeuvre,
    this.nextManoeuvre,
    this.text,
  });

  /// The coming manoeuvre.
  final RouteManoeuvre? manoeuvre;

  /// The one after it.
  final RouteManoeuvre? nextManoeuvre;

  /// Distance to [manoeuvre], metres.
  final double distanceToManoeuvreMeters;

  /// Distance left to the destination, metres.
  final double remainingMeters;

  /// Distance walked, metres.
  final double traveledMeters;

  /// Distance from the route, metres.
  final double offRouteMeters;

  /// Whether the visitor left the route. The map does not reroute by itself.
  final bool isOffRoute;

  /// Whether the visitor arrived.
  final bool hasArrived;

  /// 0 to 1 while the arrival is being confirmed.
  final double arrivalProgress;

  /// The instruction in the map's language (English or Arabic).
  final String? text;

  @override
  List<Object?> get props => [
    manoeuvre,
    nextManoeuvre,
    distanceToManoeuvreMeters,
    remainingMeters,
    traveledMeters,
    offRouteMeters,
    isOffRoute,
    hasArrived,
    arrivalProgress,
    text,
  ];

  @override
  String toString() => 'RouteGuidance(${text ?? manoeuvre?.kind.name}, ${remainingMeters.round()} m left)';
}
