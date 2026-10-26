import 'package:flutter/painting.dart';

import 'value.dart';

/// What the camera does with the visitor's position.
enum CameraMode {
  /// The camera stays where the user moves it.
  free,

  /// The camera follows the position (the default).
  follow,

  /// The camera follows the position and turns with the heading.
  followWithHeading,
}

/// Which direction the position dot points to.
enum HeadingMode {
  /// The direction of movement (the default).
  course,

  /// The compass.
  compass,

  /// No direction.
  none,
}

/// Where the built-in floor picker is shown.
enum FloorSelectorPosition {
  /// No floor picker (the default); build your own with [ProximiioMapController.floors].
  none,

  /// At the leading edge.
  leading,

  /// At the trailing edge.
  trailing,
}

/// How the first camera position is chosen.
enum InitialFraming {
  /// Frame all features of the venue (the default).
  allFeatures,

  /// Frame the first floor, as the legacy maps did.
  legacyFirstFloor,
}

/// The trail of past positions behind the dot.
class MapTrail with ValueEquality {
  /// No trail (the default).
  const MapTrail.off() : _kind = 0, _value = 0;

  /// The positions of the last [minutes].
  const MapTrail.lastMinutes(double minutes) : _kind = 1, _value = minutes;

  /// The last [count] positions.
  const MapTrail.lastFixes(int count) : _kind = 2, _value = count;

  final int _kind;
  final num _value;

  /// 0 off, 1 minutes, 2 fixes. Internal.
  int get kind => _kind;

  /// Minutes or fix count. Internal.
  num get value => _value;

  @override
  List<Object?> get props => [_kind, _value];
}

/// The venue layers to draw.
class MapLayerToggles with ValueEquality {
  /// Creates toggles; every layer is on by default.
  const MapLayerToggles({
    this.paths = true,
    this.walls = true,
    this.shops = true,
    this.pois = true,
    this.amenities = true,
    this.baseTiles = true,
  });

  /// Walking paths.
  final bool paths;

  /// Walls.
  final bool walls;

  /// Shops and rooms.
  final bool shops;

  /// Points of interest.
  final bool pois;

  /// Amenity icons.
  final bool amenities;

  /// The outdoor base map.
  final bool baseTiles;

  @override
  List<Object?> get props => [paths, walls, shops, pois, amenities, baseTiles];
}

/// Which venue features are drawn.
class MapFeatures with ValueEquality {
  /// The venue's default layers (everything but the paths).
  const MapFeatures.venueDefaults() : toggles = null, _none = false;

  /// No venue features.
  const MapFeatures.none() : toggles = null, _none = true;

  /// Only the layers in [toggles].
  const MapFeatures.only(MapLayerToggles this.toggles) : _none = false;

  /// The layers for [MapFeatures.only].
  final MapLayerToggles? toggles;
  final bool _none;

  /// Whether this is [MapFeatures.none]. Internal.
  bool get isNone => _none;

  @override
  List<Object?> get props => [toggles, _none];
}

/// Space the map keeps free of its own content: the camera framing, and on iOS also the logo and the
/// attribution (Android keeps them at MapLibre's default margins).
class MapContentInsets with ValueEquality {
  /// No insets.
  const MapContentInsets.none() : kind = 0, insets = EdgeInsetsDirectional.zero;

  /// The safe area of the device (the default).
  const MapContentInsets.safeArea() : kind = 1, insets = EdgeInsetsDirectional.zero;

  /// Exactly [insets].
  const MapContentInsets.fixed(this.insets) : kind = 2;

  /// The safe area plus [insets], for example above a bottom sheet.
  const MapContentInsets.safeAreaPlus(this.insets) : kind = 3;

  /// 0 none, 1 safe area, 2 fixed, 3 safe area plus. Internal.
  final int kind;

  /// The insets in logical pixels.
  final EdgeInsetsDirectional insets;

  @override
  List<Object?> get props => [kind, insets];
}

/// The map's own controls.
class MapChrome with ValueEquality {
  /// Creates chrome settings.
  const MapChrome({
    this.showsLogo = false,
    this.showsCompass = false,
    this.showsAttribution = true,
    this.allowsTilting = true,
  });

  /// No controls and no attribution. Show the map credits elsewhere in the app.
  static const bare = MapChrome(showsAttribution: false);

  /// The MapLibre logo.
  final bool showsLogo;

  /// The compass.
  final bool showsCompass;

  /// The map credits.
  final bool showsAttribution;

  /// Tilting with two fingers.
  final bool allowsTilting;

  @override
  List<Object?> get props => [showsLogo, showsCompass, showsAttribution, allowsTilting];
}

/// The route line.
class RouteLineStyle with ValueEquality {
  /// A line in [color], or a gradient to [toColor].
  const RouteLineStyle({
    this.color = const Color(0xFFFFAF12),
    this.toColor,
    this.completedColor = const Color(0xFF9E9E9E),
    this.width = 10,
  });

  /// The part still ahead (the gradient start with [toColor]).
  final Color color;

  /// The gradient end; `null` draws a solid line.
  final Color? toColor;

  /// The part already walked.
  final Color completedColor;

  /// Width in logical pixels.
  final double width;

  @override
  List<Object?> get props => [color, toColor, completedColor, width];
}

/// The pins at the route's floor changes.
class RouteMarkerStyle with ValueEquality {
  /// Creates a marker style.
  const RouteMarkerStyle({
    this.isVisible = true,
    this.color = const Color(0xFFFFAF12),
    this.completedColor = const Color(0xFF9E9E9E),
  });

  /// No markers.
  static const off = RouteMarkerStyle(isVisible: false);

  /// Whether markers are drawn.
  final bool isVisible;

  /// Marker colour.
  final Color color;

  /// Colour of markers already passed.
  final Color completedColor;

  @override
  List<Object?> get props => [isVisible, color, completedColor];
}

/// How geofences are drawn when [MapOptions.showsGeofences] is on.
class GeofenceStyle with ValueEquality {
  /// Creates a geofence style.
  const GeofenceStyle({
    this.fillColor = const Color(0xFF38CFE0),
    this.fillOpacity = 0.16,
    this.lineColor = const Color(0xFF1E9EB0),
    this.lineWidth = 2,
  });

  /// Fill colour.
  final Color fillColor;

  /// Fill opacity, 0 to 1.
  final double fillOpacity;

  /// Outline colour.
  final Color lineColor;

  /// Outline width in logical pixels.
  final double lineWidth;

  @override
  List<Object?> get props => [fillColor, fillOpacity, lineColor, lineWidth];
}

/// How the map looks and behaves. Every field has the native libraries' default.
class MapOptions with ValueEquality {
  /// Creates map options.
  const MapOptions({
    this.camera = CameraMode.follow,
    this.floorSelector = FloorSelectorPosition.none,
    this.trail = const MapTrail.off(),
    this.features = const MapFeatures.venueDefaults(),
    this.showsRoute = true,
    this.showsGeofences = false,
    this.contentInsets = const MapContentInsets.safeArea(),
    this.amenities = true,
    this.fallbackStyleUrl,
    this.recentreZoom,
    this.offlinePackageId,
    this.chrome,
    this.routeLineStyle,
    this.routeMarkers,
    this.geofenceStyle,
    this.initialFraming = InitialFraming.allFeatures,
    this.language,
    this.heading = HeadingMode.course,
    this.backgroundColor,
  });

  /// Camera behaviour.
  final CameraMode camera;

  /// The built-in floor picker.
  final FloorSelectorPosition floorSelector;

  /// The trail behind the dot.
  final MapTrail trail;

  /// Venue layers.
  final MapFeatures features;

  /// Draw the route set with [ProximiioMapController.showRoute] and journey legs.
  final bool showsRoute;

  /// Draw the venue's geofences.
  final bool showsGeofences;

  /// Space kept free of map content.
  final MapContentInsets contentInsets;

  /// Load the amenity icons. `false` skips that request, and a style that uses them draws a placeholder;
  /// to hide amenity icons use `MapFeatures.only(MapLayerToggles(amenities: false))`.
  final bool amenities;

  /// Style used when the organisation style cannot be loaded (native default: the MapLibre demo tiles).
  final Uri? fallbackStyleUrl;

  /// Zoom for [ProximiioMapController.recentre] (native default 18.5).
  final double? recentreZoom;

  /// An installed offline package to take the style from. Read when the map starts. When the package
  /// cannot be read, [ProximiioMapController.lastError] says so and the style comes from the API.
  final String? offlinePackageId;

  /// The map's controls; `null` keeps the default.
  final MapChrome? chrome;

  /// The route line; `null` draws it as the organisation style says. A [RouteLineStyle] replaces the
  /// style's route line.
  final RouteLineStyle? routeLineStyle;

  /// The pins at the route's floor changes; `null` keeps the default.
  final RouteMarkerStyle? routeMarkers;

  /// Geofence style; `null` keeps the default.
  final GeofenceStyle? geofenceStyle;

  /// The first camera position. Read when the map opens.
  final InitialFraming initialFraming;

  /// Language of feature titles, floor names and guidance text (`en`, `ar`); `null` follows the app's
  /// display language.
  final String? language;

  /// Direction of the dot.
  final HeadingMode heading;

  /// Colour behind the map tiles; `null` keeps the default (transparent). iOS applies a change at once;
  /// Android applies it to a new map. On Android an opaque colour makes the map render to a
  /// `SurfaceView`, which Flutter composes more slowly.
  final Color? backgroundColor;

  @override
  List<Object?> get props => [
    camera,
    floorSelector,
    trail,
    features,
    showsRoute,
    showsGeofences,
    contentInsets,
    amenities,
    fallbackStyleUrl,
    recentreZoom,
    offlinePackageId,
    chrome,
    routeLineStyle,
    routeMarkers,
    geofenceStyle,
    initialFraming,
    language,
    heading,
    backgroundColor,
  ];
}
