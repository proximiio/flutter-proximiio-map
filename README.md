# flutter_proximiio_map

The Proximi.io indoor map for Flutter: the native **Proximi.io Map v6** for iOS and Android in a platform
view, on the SDK instance of [`flutter_proximiio`](https://github.com/proximiio/flutter-proximiio). Venue
style, floors, the visitor's position, routes, turn-by-turn guidance and multi-stop journeys.

## Native versions

Each release pins exact native versions; they are built and tested together.

| flutter_proximiio_map | flutter_proximiio | iOS Map (`ProximiioMap`) | Android Map (`io.proximi.map:proximiio-map-live`) |
|---|---|---|---|
| 6.0.0-beta.1 | 6.0.0-beta.1 | 6.0.0-beta.51 | 6.0.0-beta.27 |

## Requirements

The requirements of `flutter_proximiio` apply (Flutter 3.29, iOS 15, Android minSdk 26 / compileSdk 37,
Kotlin 2.2). On iOS the map needs Flutter's Swift Package Manager support.

## Installation

```yaml
dependencies:
  flutter_proximiio:
    git:
      url: https://github.com/proximiio/flutter-proximiio
      ref: 6.0.0-beta.1
  flutter_proximiio_map:
    git:
      url: https://github.com/proximiio/flutter-proximiio-map
      ref: 6.0.0-beta.1
```

Set up `flutter_proximiio` first (repositories, `Info.plist` keys, Android build settings).

### iOS

The iOS map library ships only as a Swift package:

```sh
flutter config --enable-swift-package-manager
```

The plugin's `Package.swift` pulls `proximiio/proximiio-map-ios-binary` and the SDK. Built through
CocoaPods, the plugin compiles, but the map shows a notice and controller calls throw
`MapErrorCode.unsupported`. The iOS map pins MapLibre 6.29.0 exactly.

### Android

The map comes from `https://maven.eu.proximi.fi/releases/`, the repository the SDK uses. Nothing else is
needed.

## Usage

```dart
import 'package:flutter_proximiio/flutter_proximiio.dart';
import 'package:flutter_proximiio_map/flutter_proximiio_map.dart';

final sdk = await Proximiio.create(ProximiioConfiguration(token: token));
await sdk.requestPermissions();
await sdk.authenticate();
await sdk.loadRouteNetwork();
await sdk.start();

// in build():
ProximiioMap(
  options: const MapOptions(floorSelector: FloorSelectorPosition.trailing),
  onMapCreated: (map) async {
    await map.cameraReady;
    final here = await sdk.lastPosition(); // null before the first fix and inside privacy zones
    if (here == null) return;
    final route = await map.showRoute(
      from: here.coordinate,
      fromLevel: here.floor?.level ?? 0,
      to: destination,
    );
    print('${route.distanceMeters} m');
  },
);
```

- **Create the SDK first.** A map built before `Proximiio.create` shows a notice.
- **State** is in `ValueListenable`s on the controller: `floors`, `selectedFloor`, `cameraMode`,
  `styleSource`, `guidance`, `lastError`.
- **Journeys**: `map.startJourney(journey)` returns a `JourneyNavigator` with state, events and voice cues.
- **Errors**: route failures are `ProximiioException`s with `ProximiioErrorCode.noRoute`; other failures are
  `ProximiioMapException`s.

## Example app

```sh
cd example
cp env.example.json env.json   # put your application token in env.json (gitignored)
flutter run --dart-define-from-file=env.json
```

## Development

The bridge is generated with [Pigeon](https://pub.dev/packages/pigeon) from `pigeons/messages.dart`:

```sh
dart run pigeon --input pigeons/messages.dart
python3 tool/generate_unavailable_api.py   # the CocoaPods / no-SDK stubs
flutter analyze && flutter test
```

Generated files (`*.g.dart`, `MapMessages.g.kt`, `MapMessages.g.swift`, `UnavailableMapApi.*`) are
committed; regenerate them in the same change as the schema.

Documentation: `docs/site` (built with `node docs/site/build.mjs`, published to Partner Zone), including the
migration guide from 1.x. Changes: [CHANGELOG.md](CHANGELOG.md).
