// Runs on a device or simulator against the real SDK and map:
//   flutter test integration_test --dart-define-from-file=env.json
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_proximiio/flutter_proximiio.dart';
import 'package:flutter_proximiio_map/flutter_proximiio_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _token = String.fromEnvironment('PROXIMIIO_TOKEN');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the map shows the venue and answers the controller', (tester) async {
    final sdk = await Proximiio.create(const ProximiioConfiguration(token: _token));
    await sdk.authenticate();

    final created = Completer<ProximiioMapController>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProximiioMap(options: const MapOptions(camera: CameraMode.free), onMapCreated: created.complete),
        ),
      ),
    );

    // Frames are drawn only when the test pumps them; the platform view appears after a few.
    for (var i = 0; i < 300 && !created.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(created.isCompleted, isTrue, reason: 'onMapCreated within 30 s');
    final map = await created.future;
    for (var i = 0; i < 60 && map.styleSource.value == MapStyleSource.pending; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pump(const Duration(seconds: 2));

    debugPrint(
      'map: style ${map.styleSource.value.name}, floors ${map.floors.value}, '
      'selected ${map.selectedFloor.value.level}, error ${map.lastError.value}',
    );
    expect(map.styleSource.value, isNot(MapStyleSource.pending));

    await map.setCenter(const Coordinate(latitude: 48.1486, longitude: 17.1077), zoom: 17, animated: false);
    await tester.pump(const Duration(seconds: 1));
    final camera = await map.cameraState();
    expect(camera.zoom, closeTo(17, 0.5));

    await expectLater(map.startJourney(const Journey([])).then((journey) => journey.end()), completes);
  }, skip: _token.isEmpty);
}
