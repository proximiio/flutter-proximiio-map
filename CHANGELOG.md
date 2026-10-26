# Changelog

All notable changes to `flutter_proximiio_map` are documented here.
The format follows [Keep a Changelog 1.1](https://keepachangelog.com/en/1.1.0/), versions follow
[SemVer](https://semver.org/). Each release pins exact native map versions and one `flutter_proximiio`
version (see README).

## [Unreleased]

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
