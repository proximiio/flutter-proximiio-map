// Conversions between the public Dart types and the Pigeon transport types. Not exported.
import 'dart:ui' show Color;

import 'package:flutter_proximiio/flutter_proximiio.dart';

import 'guidance.dart';
import 'journey_models.dart';
import 'messages.g.dart';
import 'options.dart';

int _argb(Color color) => color.toARGB32();

Duration _duration(double seconds) => Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());

double _seconds(Duration duration) => duration.inMicroseconds / Duration.microsecondsPerSecond;

/// Options → transport.
MapMsgOptions toMsgOptions(MapOptions o) {
  final insets = o.contentInsets.insets;
  return MapMsgOptions(
    camera: MapMsgCameraMode.values.byName(o.camera.name),
    floorSelector: MapMsgFloorSelector.values.byName(o.floorSelector.name),
    trail: switch (o.trail.kind) {
      1 => MapMsgTrailKind.lastMinutes,
      2 => MapMsgTrailKind.lastFixes,
      _ => MapMsgTrailKind.off,
    },
    trailValue: o.trail.kind == 0 ? null : o.trail.value.toDouble(),
    features: o.features.toggles != null
        ? MapMsgFeaturesKind.only
        : (o.features.isNone ? MapMsgFeaturesKind.none : MapMsgFeaturesKind.venueDefaults),
    layerToggles: o.features.toggles == null
        ? null
        : MapMsgLayerToggles(
            paths: o.features.toggles!.paths,
            walls: o.features.toggles!.walls,
            shops: o.features.toggles!.shops,
            pois: o.features.toggles!.pois,
            amenities: o.features.toggles!.amenities,
            baseTiles: o.features.toggles!.baseTiles,
          ),
    showsRoute: o.showsRoute,
    showsGeofences: o.showsGeofences,
    insets: MapMsgInsetsKind.values[o.contentInsets.kind],
    insetValues: o.contentInsets.kind >= 2
        ? MapMsgEdgeInsets(top: insets.top, leading: insets.start, bottom: insets.bottom, trailing: insets.end)
        : null,
    amenities: o.amenities,
    fallbackStyleUrl: o.fallbackStyleUrl?.toString(),
    recentreZoom: o.recentreZoom,
    offlinePackageId: o.offlinePackageId,
    chrome: o.chrome == null
        ? null
        : MapMsgChrome(
            showsLogo: o.chrome!.showsLogo,
            showsCompass: o.chrome!.showsCompass,
            showsAttribution: o.chrome!.showsAttribution,
            allowsTilting: o.chrome!.allowsTilting,
          ),
    routeLineStyle: o.routeLineStyle == null
        ? null
        : MapMsgRouteLineStyle(
            color: _argb(o.routeLineStyle!.color),
            toColor: o.routeLineStyle!.toColor == null ? null : _argb(o.routeLineStyle!.toColor!),
            completedColor: _argb(o.routeLineStyle!.completedColor),
            width: o.routeLineStyle!.width,
          ),
    routeMarkers: o.routeMarkers == null
        ? null
        : MapMsgRouteMarkerStyle(
            isVisible: o.routeMarkers!.isVisible,
            color: _argb(o.routeMarkers!.color),
            completedColor: _argb(o.routeMarkers!.completedColor),
          ),
    geofenceStyle: o.geofenceStyle == null
        ? null
        : MapMsgGeofenceStyle(
            fillColor: _argb(o.geofenceStyle!.fillColor),
            fillOpacity: o.geofenceStyle!.fillOpacity,
            lineColor: _argb(o.geofenceStyle!.lineColor),
            lineWidth: o.geofenceStyle!.lineWidth,
          ),
    initialFraming: MapMsgInitialFraming.values.byName(o.initialFraming.name),
    language: o.language,
    heading: MapMsgHeadingMode.values.byName(o.heading.name),
    backgroundColor: o.backgroundColor == null ? null : _argb(o.backgroundColor!),
  );
}

/// Coordinate → transport.
MapMsgCoordinate toMsgCoordinate(Coordinate c) => MapMsgCoordinate(latitude: c.latitude, longitude: c.longitude);

/// Transport → coordinate.
Coordinate fromMsgCoordinate(MapMsgCoordinate c) => Coordinate(latitude: c.latitude, longitude: c.longitude);

/// Route options → transport (by their Dart names, which the native sides read).
MapMsgRouteOptions toMsgRouteOptions(RouteOptions o) =>
    MapMsgRouteOptions(profile: o.profile.name, avoid: [for (final a in o.avoid) a.name]);

/// Follow rules → transport.
MapMsgFollowRules toMsgFollowRules(RouteFollowRules r) => MapMsgFollowRules(
  arrivalRadiusMeters: r.arrivalRadiusMeters,
  arrivalDwellSeconds: _seconds(r.arrivalDwell),
  offRouteMeters: r.offRouteMeters,
  offRouteFixes: r.offRouteFixes,
);

LevelChange _levelChange(MapMsgLevelChange c) => LevelChange(
  featureType: c.featureType,
  fromLevel: c.fromLevel,
  toLevel: c.toLevel,
  coordinate: fromMsgCoordinate(c.coordinate),
);

/// Transport → [ComputedRoute] of flutter_proximiio.
ComputedRoute fromMsgRoute(MapMsgRoute r) => ComputedRoute(
  coordinates: [for (final c in r.coordinates) fromMsgCoordinate(c)],
  distanceMeters: r.distanceMeters,
  segments: [
    for (final s in r.segments)
      RouteSegment(start: fromMsgCoordinate(s.start), end: fromMsgCoordinate(s.end), distanceMeters: s.distanceMeters),
  ],
  level: r.level,
  levelChanges: [for (final c in r.levelChanges) _levelChange(c)],
  instructions: [
    for (final i in r.instructions)
      RouteInstruction(
        kind: RouteInstructionKind.values.asNameMap()[i.kind] ?? RouteInstructionKind.continueStraight,
        coordinate: fromMsgCoordinate(i.coordinate),
        distanceMeters: i.distanceMeters,
        level: i.level,
        duration: _duration(i.durationSeconds),
        levelChange: i.levelChange == null ? null : _levelChange(i.levelChange!),
      ),
  ],
  duration: _duration(r.durationSeconds),
);

RouteManoeuvre _manoeuvre(MapMsgManoeuvre m) => RouteManoeuvre(
  kind: ManoeuvreKind.values.asNameMap()[m.kind] ?? ManoeuvreKind.unknown,
  coordinate: fromMsgCoordinate(m.coordinate),
  level: m.level,
  legMeters: m.legMeters,
  levelChange: m.levelChange == null ? null : _levelChange(m.levelChange!),
);

/// Transport → [RouteGuidance].
RouteGuidance fromMsgGuidance(MapMsgGuidance g) => RouteGuidance(
  manoeuvre: g.manoeuvre == null ? null : _manoeuvre(g.manoeuvre!),
  nextManoeuvre: g.nextManoeuvre == null ? null : _manoeuvre(g.nextManoeuvre!),
  distanceToManoeuvreMeters: g.distanceToManoeuvreMeters,
  remainingMeters: g.remainingMeters,
  traveledMeters: g.traveledMeters,
  offRouteMeters: g.offRouteMeters,
  isOffRoute: g.isOffRoute,
  hasArrived: g.hasArrived,
  arrivalProgress: g.arrivalProgress,
  text: g.text,
);

// ── Journeys ──

/// Stop → transport.
MapMsgStop toMsgStop(JourneyStop s) => MapMsgStop(
  id: s.id,
  title: s.title,
  coordinate: toMsgCoordinate(s.coordinate),
  level: s.level,
  poiId: s.poiId,
  group: s.group,
  iconName: s.iconName,
  kind: MapMsgStopKind.values.byName(s.kind.name),
  state: MapMsgStopState.values.byName(s.state.name),
);

/// Transport → stop.
JourneyStop fromMsgStop(MapMsgStop s) => JourneyStop(
  id: s.id,
  title: s.title,
  coordinate: fromMsgCoordinate(s.coordinate),
  level: s.level,
  poiId: s.poiId,
  group: s.group,
  iconName: s.iconName,
  kind: JourneyStopKind.values.byName(s.kind.name),
  state: JourneyStopState.values.byName(s.state.name),
);

/// Journey → transport.
MapMsgJourney toMsgJourney(Journey j) => MapMsgJourney(stops: [for (final s in j.stops) toMsgStop(s)]);

/// Rules → transport.
MapMsgJourneyRules toMsgJourneyRules(JourneyRules r) => MapMsgJourneyRules(
  advanceOnDepartureMeters: r.advanceOnDepartureMeters,
  rerouteCooldownSeconds: _seconds(r.rerouteCooldown),
  walkingSpeedMetersPerSecond: r.walkingSpeedMetersPerSecond,
);

Duration? _optionalDuration(double? seconds) => seconds == null ? null : _duration(seconds);

/// Transport → [JourneyState].
JourneyState fromMsgJourneyState(MapMsgJourneyState s) => JourneyState(
  journey: Journey([for (final stop in s.journey.stops) fromMsgStop(stop)]),
  overview: JourneyOverview(
    remainingStopIds: s.overview.remainingStopIds,
    legs: [
      for (final leg in s.overview.legs)
        JourneyLeg(
          destinationStopId: leg.destinationStopId,
          originStopId: leg.originStopId,
          meters: leg.meters,
          isUnreachable: leg.isUnreachable,
          isActive: leg.isActive,
          duration: _optionalDuration(leg.durationSeconds),
        ),
    ],
    remainingMeters: s.overview.remainingMeters,
    eta: _duration(s.overview.etaSeconds),
    activeLegRemainingMeters: s.overview.activeLegRemainingMeters,
    activeLegEta: _optionalDuration(s.overview.activeLegEtaSeconds),
    unmeasuredLegCount: s.overview.unmeasuredLegCount,
    unreachableStopIds: s.overview.unreachableStopIds,
  ),
  deviation: s.deviation == null
      ? null
      : JourneyDeviation(
          episode: s.deviation!.episode,
          since: DateTime.fromMillisecondsSinceEpoch(s.deviation!.sinceMs, isUtc: true),
          distanceMeters: s.deviation!.distanceMeters,
          isOnRouteFloor: s.deviation!.isOnRouteFloor,
        ),
  activeStopId: s.activeStopId,
  detourStopId: s.detourStopId,
  hasArrived: s.hasArrived,
  isFinished: s.isFinished,
  reorderableStopIds: s.reorderableStopIds,
  noRouteReasons: {
    for (final entry in s.noRouteStopIds.entries) entry.key: NoRouteReason.values.asNameMap()[entry.value],
  },
);

/// Transport → [JourneyEvent].
JourneyEvent fromMsgNotice(MapMsgJourneyNotice n) {
  final stop = n.stop == null ? null : fromMsgStop(n.stop!);
  final distance = n.distanceMeters ?? 0;
  final duration = _duration(n.durationSeconds ?? 0);
  return switch (n.kind) {
    'leftRoute' => JourneyLeftRoute(distance),
    'farFromRoute' => JourneyFarFromRoute(distance),
    'offRouteTooLong' => JourneyOffRouteTooLong(duration),
    'returnedToRoute' => const JourneyReturnedToRoute(),
    'detourOverstayed' when stop != null => JourneyDetourOverstayed(stop, duration),
    'detourStarted' when stop != null => JourneyDetourStarted(stop),
    'detourEnded' when stop != null => JourneyDetourEnded(stop, completed: n.completed ?? false),
    'stopReached' when stop != null => JourneyStopReached(stop),
    'stopPassed' when stop != null => JourneyStopPassed(stop),
    'stopSkipped' when stop != null => JourneyStopSkipped(stop),
    'legChanged' when stop != null => JourneyLegChanged(stop, reason: n.reason ?? 'unknown'),
    'rerouted' when stop != null => JourneyRerouted(stop),
    'journeyFinished' => const JourneyFinished(),
    _ => JourneyUnknownEvent(n.kind),
  };
}

/// Transport → [JourneyCue].
JourneyCue fromMsgCue(MapMsgJourneyCue c) => JourneyCue(
  kind: JourneyCueKind.values.asNameMap()[c.kind] ?? JourneyCueKind.unknown,
  text: c.text,
  distanceMeters: c.distanceMeters,
);

/// Transport → [JourneyOrderProposal].
JourneyOrderProposal fromMsgProposal(MapMsgProposal p) => JourneyOrderProposal(
  id: p.id,
  order: p.order,
  pinnedStopIds: p.pinnedStopIds,
  currentMeters: p.currentMeters,
  proposedMeters: p.proposedMeters,
  currentDuration: _duration(p.currentSeconds),
  proposedDuration: _duration(p.proposedSeconds),
);
