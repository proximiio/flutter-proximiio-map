// Bridge schema between Dart and the native Proximi.io Map v6 libraries.
//
// Regenerate after any change:
//   dart run pigeon --input pigeons/messages.dart
//
// Flow: Dart calls `MapRegistryApi.prepare(options)` and gets a handle; it creates the platform view
// with the handle as its creation parameter; the native factory builds the map with the prepared
// options. Every per-map API and event channel uses the handle as its channel suffix.
//
// Transport types carry the prefix `MapMsg` so the generated Swift/Kotlin types do not clash with
// the map libraries' own `MapOptions`, `MapColor`, `MapCoordinate`. Colours are ARGB integers,
// times are milliseconds since the epoch, durations seconds, lengths metres.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartPackageName: 'flutter_proximiio_map',
    kotlinOut: 'android/src/main/kotlin/io/proximi/flutter_proximiio_map/MapMessages.g.kt',
    kotlinOptions: KotlinOptions(package: 'io.proximi.flutter_proximiio_map', errorClassName: 'MapFlutterError'),
    swiftOut: 'ios/flutter_proximiio_map/Sources/flutter_proximiio_map/MapMessages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'MapFlutterError'),
  ),
)
// ── Options ──────────────────────────────────────────────────────────────────

enum MapMsgCameraMode { free, follow, followWithHeading }

enum MapMsgHeadingMode { course, compass, none }

enum MapMsgFloorSelector { none, leading, trailing }

enum MapMsgInitialFraming { allFeatures, legacyFirstFloor }

enum MapMsgTrailKind { off, lastMinutes, lastFixes }

enum MapMsgFeaturesKind { venueDefaults, none, only }

enum MapMsgInsetsKind { none, safeArea, fixed, safeAreaPlus }

class MapMsgEdgeInsets {
  MapMsgEdgeInsets({required this.top, required this.leading, required this.bottom, required this.trailing});

  double top;
  double leading;
  double bottom;
  double trailing;
}

class MapMsgLayerToggles {
  MapMsgLayerToggles({
    required this.paths,
    required this.walls,
    required this.shops,
    required this.pois,
    required this.amenities,
    required this.baseTiles,
  });

  bool paths;
  bool walls;
  bool shops;
  bool pois;
  bool amenities;
  bool baseTiles;
}

class MapMsgChrome {
  MapMsgChrome({
    required this.showsLogo,
    required this.showsCompass,
    required this.showsAttribution,
    required this.allowsTilting,
  });

  bool showsLogo;
  bool showsCompass;
  bool showsAttribution;
  bool allowsTilting;
}

/// Solid when [toColor] is null, a gradient otherwise.
class MapMsgRouteLineStyle {
  MapMsgRouteLineStyle({required this.color, required this.completedColor, required this.width});

  int color;
  int? toColor;
  int completedColor;
  double width;
}

class MapMsgRouteMarkerStyle {
  MapMsgRouteMarkerStyle({required this.isVisible, required this.color, required this.completedColor});

  bool isVisible;
  int color;
  int completedColor;
}

class MapMsgGeofenceStyle {
  MapMsgGeofenceStyle({
    required this.fillColor,
    required this.fillOpacity,
    required this.lineColor,
    required this.lineWidth,
  });

  int fillColor;
  double fillOpacity;
  int lineColor;
  double lineWidth;
}

class MapMsgOptions {
  MapMsgOptions({
    required this.camera,
    required this.floorSelector,
    required this.trail,
    required this.features,
    required this.showsRoute,
    required this.showsGeofences,
    required this.insets,
    required this.amenities,
    required this.initialFraming,
    required this.heading,
  });

  MapMsgCameraMode camera;
  MapMsgFloorSelector floorSelector;
  MapMsgTrailKind trail;

  /// Minutes for `lastMinutes`, a fix count for `lastFixes`.
  double? trailValue;
  MapMsgFeaturesKind features;
  MapMsgLayerToggles? layerToggles;
  bool showsRoute;
  bool showsGeofences;
  MapMsgInsetsKind insets;
  MapMsgEdgeInsets? insetValues;
  bool amenities;
  String? fallbackStyleUrl;
  double? recentreZoom;
  String? offlinePackageId;
  MapMsgChrome? chrome;
  MapMsgRouteLineStyle? routeLineStyle;
  MapMsgRouteMarkerStyle? routeMarkers;
  MapMsgGeofenceStyle? geofenceStyle;
  MapMsgInitialFraming initialFraming;
  String? language;
  MapMsgHeadingMode heading;
  int? backgroundColor;
}

// ── Map state ────────────────────────────────────────────────────────────────

class MapMsgCoordinate {
  MapMsgCoordinate({required this.latitude, required this.longitude});

  double latitude;
  double longitude;
}

class MapMsgFloor {
  MapMsgFloor({required this.level});

  double level;
  String? name;
}

class MapMsgCameraState {
  MapMsgCameraState({required this.mode});

  MapMsgCoordinate? center;
  double? zoom;
  double? direction;
  MapMsgCameraMode mode;
}

enum MapMsgStyleSourceKind { pending, cache, organization, offlinePackage, fallback }

// ── Routes and guidance ──────────────────────────────────────────────────────

/// Route profile and avoidances by their Dart names (`wheelchair`, `staircases`, …).
class MapMsgRouteOptions {
  MapMsgRouteOptions({required this.profile, required this.avoid});

  String profile;
  List<String> avoid;
}

class MapMsgLevelChange {
  MapMsgLevelChange({
    required this.featureType,
    required this.fromLevel,
    required this.toLevel,
    required this.coordinate,
  });

  String featureType;
  double fromLevel;
  double toLevel;
  MapMsgCoordinate coordinate;
}

/// [kind] is the `RouteInstructionKind` / manoeuvre name (`turnLeft`, `levelChange`, …).
class MapMsgInstruction {
  MapMsgInstruction({
    required this.kind,
    required this.coordinate,
    required this.distanceMeters,
    required this.level,
    required this.durationSeconds,
  });

  String kind;
  MapMsgCoordinate coordinate;
  double distanceMeters;
  double level;
  double durationSeconds;
  MapMsgLevelChange? levelChange;
}

class MapMsgSegment {
  MapMsgSegment({required this.start, required this.end, required this.distanceMeters});

  MapMsgCoordinate start;
  MapMsgCoordinate end;
  double distanceMeters;
}

class MapMsgRoute {
  MapMsgRoute({
    required this.coordinates,
    required this.distanceMeters,
    required this.segments,
    required this.level,
    required this.levelChanges,
    required this.instructions,
    required this.durationSeconds,
  });

  List<MapMsgCoordinate> coordinates;
  double distanceMeters;
  List<MapMsgSegment> segments;
  double level;
  List<MapMsgLevelChange> levelChanges;
  List<MapMsgInstruction> instructions;
  double durationSeconds;
}

class MapMsgFollowRules {
  MapMsgFollowRules({
    required this.arrivalDwellSeconds,
    required this.offRouteMeters,
    required this.offRouteFixes,
  });

  /// Fixed arrival radius; `null` keeps the accuracy-based radius of the venue preset.
  double? arrivalRadiusMeters;
  double arrivalDwellSeconds;
  double offRouteMeters;
  int offRouteFixes;
}

class MapMsgManoeuvre {
  MapMsgManoeuvre({required this.kind, required this.coordinate, required this.level, required this.legMeters});

  /// `start`, `continueStraight`, `turnLeft`, …, `levelChange`, `arrive`.
  String kind;
  MapMsgCoordinate coordinate;
  double level;
  double legMeters;
  MapMsgLevelChange? levelChange;
}

class MapMsgGuidance {
  MapMsgGuidance({
    required this.distanceToManoeuvreMeters,
    required this.remainingMeters,
    required this.traveledMeters,
    required this.offRouteMeters,
    required this.isOffRoute,
    required this.hasArrived,
    required this.arrivalProgress,
  });

  MapMsgManoeuvre? manoeuvre;
  MapMsgManoeuvre? nextManoeuvre;
  double distanceToManoeuvreMeters;
  double remainingMeters;
  double traveledMeters;
  double offRouteMeters;
  bool isOffRoute;
  bool hasArrived;
  double arrivalProgress;

  /// The instruction in the map's language (English or Arabic), from the native text builder.
  String? text;
}

// ── Journeys ─────────────────────────────────────────────────────────────────

enum MapMsgStopKind { planned, detour }

enum MapMsgStopState { pending, active, reached, done, skipped }

class MapMsgStop {
  MapMsgStop({
    required this.id,
    required this.title,
    required this.coordinate,
    required this.kind,
    required this.state,
  });

  String id;
  String title;
  MapMsgCoordinate coordinate;
  double? level;
  String? poiId;
  String? group;
  String? iconName;
  MapMsgStopKind kind;
  MapMsgStopState state;
}

class MapMsgJourney {
  MapMsgJourney({required this.stops});

  List<MapMsgStop> stops;
}

class MapMsgJourneyRules {
  MapMsgJourneyRules({required this.rerouteCooldownSeconds, required this.walkingSpeedMetersPerSecond});

  /// Advance to the next stop after walking this far from the reached one; `null` advances manually.
  double? advanceOnDepartureMeters;
  double rerouteCooldownSeconds;
  double walkingSpeedMetersPerSecond;
}

class MapMsgLeg {
  MapMsgLeg({required this.destinationStopId, required this.isActive, required this.isUnreachable});

  String destinationStopId;
  String? originStopId;
  double? meters;
  bool isUnreachable;
  bool isActive;
  double? durationSeconds;
}

class MapMsgOverview {
  MapMsgOverview({
    required this.remainingStopIds,
    required this.legs,
    required this.remainingMeters,
    required this.etaSeconds,
    required this.unmeasuredLegCount,
    required this.unreachableStopIds,
  });

  List<String> remainingStopIds;
  List<MapMsgLeg> legs;
  double remainingMeters;
  double etaSeconds;
  double? activeLegRemainingMeters;
  double? activeLegEtaSeconds;
  int unmeasuredLegCount;
  List<String> unreachableStopIds;
}

class MapMsgDeviation {
  MapMsgDeviation({
    required this.episode,
    required this.sinceMs,
    required this.distanceMeters,
    required this.isOnRouteFloor,
  });

  int episode;
  int sinceMs;
  double distanceMeters;
  bool isOnRouteFloor;
}

class MapMsgJourneyState {
  MapMsgJourneyState({
    required this.journey,
    required this.overview,
    required this.hasArrived,
    required this.isFinished,
    required this.noRouteStopIds,
  });

  MapMsgJourney journey;
  MapMsgOverview overview;
  MapMsgDeviation? deviation;
  String? activeStopId;
  String? detourStopId;
  bool hasArrived;
  bool isFinished;

  /// Stops no route leads to, with the SDK's `NoRouteReason` name.
  Map<String, String> noRouteStopIds;
}

enum MapMsgOrderOrigin { activeStop, visitor }

enum MapMsgOrderStrategy { quickestWalk, floorThenGallery }

/// A proposed stop order. The native side keeps the proposal under [id] for `applyProposal`.
class MapMsgProposal {
  MapMsgProposal({
    required this.id,
    required this.order,
    required this.pinnedStopIds,
    required this.currentMeters,
    required this.proposedMeters,
    required this.currentSeconds,
    required this.proposedSeconds,
  });

  int id;
  List<String> order;
  List<String> pinnedStopIds;
  double currentMeters;
  double proposedMeters;
  double currentSeconds;
  double proposedSeconds;
}

// ── Events ───────────────────────────────────────────────────────────────────

sealed class MapMsgEvent {}

class MapMsgCameraReady extends MapMsgEvent {
  MapMsgCameraReady({required this.isReady});

  bool isReady;
}

class MapMsgStyleSourceChanged extends MapMsgEvent {
  MapMsgStyleSourceChanged({required this.kind});

  MapMsgStyleSourceKind kind;

  /// The offline package id, or the reason of a fallback.
  String? detail;
}

class MapMsgFeatureTapped extends MapMsgEvent {
  MapMsgFeatureTapped({required this.featureIds, required this.coordinate});

  List<String> featureIds;
  MapMsgCoordinate coordinate;
}

class MapMsgFloorsChanged extends MapMsgEvent {
  MapMsgFloorsChanged({required this.floors});

  List<MapMsgFloor> floors;
}

class MapMsgSelectedFloorChanged extends MapMsgEvent {
  MapMsgSelectedFloorChanged({required this.level, required this.isPinned});

  double level;
  bool isPinned;
}

class MapMsgCameraModeChanged extends MapMsgEvent {
  MapMsgCameraModeChanged({required this.mode});

  MapMsgCameraMode mode;
}

class MapMsgGuidanceChanged extends MapMsgEvent {
  MapMsgGuidance? guidance;
}

class MapMsgErrorChanged extends MapMsgEvent {
  String? message;
}

sealed class MapMsgJourneyEvent {}

class MapMsgJourneyStateChanged extends MapMsgJourneyEvent {
  MapMsgJourneyStateChanged({required this.state});

  MapMsgJourneyState state;
}

class MapMsgJourneyGuidanceChanged extends MapMsgJourneyEvent {
  MapMsgJourneyGuidance? guidance;
}

/// Wraps the guidance so a null guidance can travel inside an event.
class MapMsgJourneyGuidance {
  MapMsgJourneyGuidance({required this.guidance});

  MapMsgGuidance guidance;
}

/// One `JourneyEvent`. [kind] is the case name (`stopReached`, `leftRoute`, `legChanged`, …).
class MapMsgJourneyNotice extends MapMsgJourneyEvent {
  MapMsgJourneyNotice({required this.kind});

  String kind;
  MapMsgStop? stop;
  double? distanceMeters;
  double? durationSeconds;
  bool? completed;

  /// For `legChanged`: `started`, `advanced`, `skipped`, `detour`, …
  String? reason;
}

/// A spoken-style cue (`manoeuvre`, `levelChange`, `approachingDestination`, `arrived`).
class MapMsgJourneyCue extends MapMsgJourneyEvent {
  MapMsgJourneyCue({required this.kind, required this.text, required this.distanceMeters});

  String kind;
  String text;
  double distanceMeters;
}

// ── APIs ─────────────────────────────────────────────────────────────────────

/// Global: prepares a map before its platform view exists.
@HostApi()
abstract class MapRegistryApi {
  /// Stores [options] and returns the handle to pass to the platform view.
  int prepare(MapMsgOptions options);
}

/// One map, addressed by its handle as the channel suffix.
///
/// Errors: `notConfigured` (no SDK instance: call `Proximiio.create` first), `notReady` (the view
/// is gone), `noJourney`, `unknownProposal`, `invalidArgument`, `noRoute` (details as in
/// flutter_proximiio), `unsupported`.
@HostApi()
abstract class MapHostApi {
  void setOptions(MapMsgOptions options);

  MapMsgCameraState cameraState();

  void setCenter(MapMsgCoordinate center, double? zoom, bool animated);

  void setZoom(double zoom, bool animated);

  void zoomBy(double delta, bool animated);

  void fitCoordinates(List<MapMsgCoordinate> coordinates, bool animated);

  void setHeading(double? degrees);

  void recentre(double? zoom, bool? withHeading);

  void showVenue(bool animated);

  List<MapMsgFloor> floors();

  double selectedFloor();

  void selectFloor(double level);

  void followMyFloor();

  void setHiddenFeatureIds(List<String> ids);

  void clearTrail();

  /// Computes the route with the SDK and shows it.
  @async
  MapMsgRoute showRoute(
    MapMsgCoordinate from,
    double fromLevel,
    MapMsgCoordinate to,
    double toLevel,
    MapMsgRouteOptions options,
  );

  void clearRoute();

  /// `null` turns guidance off.
  void setGuidanceRules(MapMsgFollowRules? rules);

  String? instructionText(String? destinationTitle);

  // ── Journey ──

  @async
  void startJourney(MapMsgJourney journey, MapMsgJourneyRules rules, MapMsgRouteOptions routeOptions);

  void endJourney();

  MapMsgJourneyState? journeyState();

  @async
  void advance();

  @async
  void skip();

  @async
  bool skipStop(String stopId);

  @async
  bool markDone(String stopId);

  @async
  bool reopen(String stopId);

  @async
  bool activate(String stopId);

  @async
  void detour(MapMsgStop stop);

  @async
  void cancelDetour();

  @async
  void moveStop(String stopId, int toIndex);

  @async
  bool addStop(MapMsgStop stop);

  @async
  bool insertStop(MapMsgStop stop, int index);

  @async
  bool removeStop(String stopId);

  @async
  bool replaceStop(MapMsgStop stop);

  @async
  bool updateJourney(MapMsgJourney journey);

  @async
  MapMsgProposal? proposeOrder(MapMsgOrderOrigin origin, List<String> pinnedStopIds, MapMsgOrderStrategy strategy);

  @async
  bool applyProposal(int proposalId);

  @async
  void resumeJourney();

  @async
  MapMsgProposal? replanFromHere(List<String> pinnedStopIds);

  @async
  void setJourneyRouteOptions(MapMsgRouteOptions options);

  void fitActiveLeg(bool animated);

  void fitJourney(bool animated);

  /// Releases the map: the view, the session and a running journey.
  void dispose();
}

/// Per-map events; the instance name is the handle. On listen the native side sends the current
/// state (floors, selected floor, camera mode, style source, error, guidance; the journey state),
/// so a late listener misses nothing that is still true.
@EventChannelApi()
abstract class MapEventApi {
  MapMsgEvent mapEvents();

  MapMsgJourneyEvent journeyEvents();
}
