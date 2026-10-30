# Changelog

All notable changes to `flutter_proximiio_map` are documented here.
The format follows [Keep a Changelog 1.1](https://keepachangelog.com/en/1.1.0/), versions follow
[SemVer](https://semver.org/). Each release pins exact native map versions and one `flutter_proximiio`
version (see README).

## [Unreleased]

## [6.0.0-beta.6] - 2026-10-30

### Changed
- Depends on `flutter_proximiio` 6.0.0-beta.6.
- iOS: the map builds on `ProximiioMap` 6.0.0-beta.60 and the iOS SDK 6.0.0-beta.68 (was 6.0.0-beta.57 and
  6.0.0-beta.67). Android: `proximiio-map-live` 6.0.0-beta.37 (was 6.0.0-beta.31), with the Android SDK
  6.0.0-beta.36 that flutter_proximiio brings.
- Faster, both: a map reads the venue's features once when it opens, and the SDKs answer it from memory.
- Faster, Android: the venue's features are encoded once per process, as soon as the SDK has them, and only what
  changed is encoded again when a map opens later. MapLibre fetches up to 20 requests at once from the API host
  (was 5). The encoded venue stays in memory after the map closes, a few MB for a large venue.
- Both: when the style's metadata has `proximiio:raster:bounds`, the map asks for no raster tile outside it.

## [6.0.0-beta.5] - 2026-10-29

### Changed
- Depends on `flutter_proximiio` 6.0.0-beta.5.
- iOS: the map builds on `ProximiioMap` 6.0.0-beta.57 and the iOS SDK 6.0.0-beta.67 (was 6.0.0-beta.55 and
  6.0.0-beta.66). Android: `proximiio-map-live` 6.0.0-beta.31 (was 6.0.0-beta.28), with the Android SDK
  6.0.0-beta.35 that flutter_proximiio brings.
- Android: when two places have a floor at the same level, the floor of the place the visitor is in names the
  level, otherwise the floor with the smallest id, as on iOS since 6.0.0-beta.4.
- Android: custom raster tiles set in the style in the Portal are drawn, as on iOS.
- Both: floors and places deleted on the server leave the map, through the SDKs' venue data changes.
- Android: when the API keeps refusing the token and the SDK deletes its data, the map drops the venue, as on iOS.

## [6.0.0-beta.4] - 2026-10-28

### Changed
- Depends on `flutter_proximiio` 6.0.0-beta.4.
- iOS: the map builds on `ProximiioMap` 6.0.0-beta.55 (was 6.0.0-beta.54), still on the iOS SDK 6.0.0-beta.66.
  Android: `proximiio-map-live` 6.0.0-beta.28 (was 6.0.0-beta.27), still on the Android SDK 6.0.0-beta.31.
- iOS: when two places have a floor at the same level, the floor of the place the visitor is in names the
  level, otherwise the floor with the smallest id. Before, the last floor named it. Android follows in a later
  map release.
- iOS: custom raster tiles set in the style in the Portal are drawn.
- Android: a map created after the last position shows the dot at once; before, it waited for the next one.

## [6.0.0-beta.3] - 2026-10-27

### Changed
- Depends on `flutter_proximiio` 6.0.0-beta.3.
- iOS: the map builds on `ProximiioMap` 6.0.0-beta.54 and the iOS SDK 6.0.0-beta.66 (was 6.0.0-beta.51 and
  6.0.0-beta.64). Android stays on `proximiio-map-live` 6.0.0-beta.27.
- iOS: a map created after the last position shows the dot at once; before, it waited for the next one.
- iOS: when the SDK starts without a connection, the map draws the stored venue data.
- iOS: when the API has refused the token for at least two hours and the SDK deletes its data, the map
  drops the venue, the route and the dot, and deletes its style and tile caches.

## [6.0.0-beta.2] - 2026-10-26

### Changed
- BREAKING: depends on `flutter_proximiio` 6.0.0-beta.2; the minimum is Flutter 3.44 / Dart 3.12.
- The Android plugin migrates to the Android Gradle Plugin's built-in Kotlin, as Flutter requires of
  plugins. Apps build with and without built-in Kotlin, on the Android Gradle Plugin 8.13 or newer.
- The Android build files use the Kotlin DSL.
- The example app uses the Android toolchain of the current Flutter template (Gradle 9.3, Android
  Gradle Plugin 9.1, Kotlin 2.4) with built-in Kotlin.

## [6.0.0-beta.1] - 2026-10-26

### Added
- `ProximiioMap` widget: the native Proximi.io map in a platform view, on the SDK instance of
  `flutter_proximiio`.
- `MapOptions`: camera mode, heading mode, floor selector, trail, feature layers, route and geofence drawing
  and styles, content insets, chrome, initial framing, language, fallback style, offline package style.
- `ProximiioMapController`: state as `ValueListenable`s (`floors`, `selectedFloor`, `cameraMode`,
  `styleSource`, `guidance`, `lastError`), `featureTaps`, `cameraReady`; camera (`setCenter`, `setZoom`,
  `zoomBy`, `fitCoordinates`, `recentre`, `showVenue`, `setHeading`), floors (`selectFloor`,
  `followMyFloor`), features (`setHiddenFeatureIds`, `clearTrail`).
- Routes: `showRoute` / `clearRoute` returning the SDK's `ComputedRoute`; turn-by-turn guidance
  (`RouteGuidance`, `RouteManoeuvre`, `setGuidanceRules`, `instructionText`).
- Journeys: `startJourney` returns a `JourneyNavigator` with `state`, `guidance`, `events` (sealed
  `JourneyEvent`), voice `cues`, stop progress, detours, plan edits and reordering proposals.
  `JourneyState.reorderableStops` is the index space of `moveStop` and `insertStop`;
  `routeNetworkChanged()` routes the journey again, and the map calls it when the SDK reports new
  features. `startJourney` calls run one after another and keep the rules of `setGuidanceRules`.
- The map follows `stop()` / `start()` of its SDK instance and asks for a new map when `Proximiio.create`
  replaced it.
- `ProximiioMapException` with `MapErrorCode`; route failures are `ProximiioException`s with
  `ProximiioErrorCode.noRoute`. A route call replaced by a later one fails with `superseded`;
  `cameraReady` fails when the map cannot be shown.
- Documentation site (`docs/site`) in the style of the iOS and Android map docs, for Partner Zone.

### Changed
- BREAKING: the WebView map is replaced by the native map (iOS `ProximiioMap` 6.0.0-beta.51, Android
  `io.proximi.map:proximiio-map-live` 6.0.0-beta.27). `ProximiioMapWidget` and its token, `mapDefaults` and
  callbacks are removed; see the migration guide (`docs/site/content/reference/migration.html`).
- BREAKING: depends on `flutter_proximiio` 6.0.0-beta.1; minimum platforms are iOS 15 and Android API 26. On
  iOS the map needs Flutter's Swift Package Manager support.
- The example app uses the UIScene lifecycle on iOS (Flutter 3.38 or newer).

### Removed
- The `webview_flutter` dependency.

## [1.0.0]

### Added
- First release: the Proximi.io web map in a WebView.
