import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_proximiio/flutter_proximiio.dart';
import 'package:flutter_proximiio_map/flutter_proximiio_map.dart';
import 'package:flutter_proximiio_map/src/controller.dart';
import 'package:flutter_proximiio_map/src/convert.dart';
import 'package:flutter_proximiio_map/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMapApi extends MapHostApi {
  final calls = <String>[];
  PlatformException? failWith;

  Future<T> _answer<T>(String call, T value) async {
    calls.add(call);
    if (failWith != null) throw failWith!;
    return value;
  }

  @override
  Future<void> selectFloor(double level) => _answer('selectFloor($level)', null);

  @override
  Future<MapMsgRoute> showRoute(
    MapMsgCoordinate from,
    double fromLevel,
    MapMsgCoordinate to,
    double toLevel,
    MapMsgRouteOptions options,
  ) => _answer(
    'showRoute($fromLevel→$toLevel ${options.profile} ${options.avoid})',
    MapMsgRoute(
      coordinates: [from, to],
      distanceMeters: 30,
      segments: [MapMsgSegment(start: from, end: to, distanceMeters: 30)],
      level: fromLevel,
      levelChanges: const [],
      instructions: [
        MapMsgInstruction(kind: 'arrive', coordinate: to, distanceMeters: 30, level: toLevel, durationSeconds: 25),
      ],
      durationSeconds: 25,
    ),
  );

  @override
  Future<void> startJourney(MapMsgJourney journey, MapMsgJourneyRules rules, MapMsgRouteOptions routeOptions) =>
      _answer('startJourney(${journey.stops.length}, ${rules.advanceOnDepartureMeters})', null);

  @override
  Future<MapMsgProposal?> proposeOrder(
    MapMsgOrderOrigin origin,
    List<String> pinnedStopIds,
    MapMsgOrderStrategy strategy,
  ) => _answer(
    'proposeOrder',
    MapMsgProposal(
      id: 7,
      order: const ['b', 'a'],
      pinnedStopIds: const [],
      currentMeters: 100,
      proposedMeters: 60,
      currentSeconds: 80,
      proposedSeconds: 50,
    ),
  );

  @override
  Future<bool> applyProposal(int proposalId) => _answer('applyProposal($proposalId)', true);

  @override
  Future<void> dispose() => _answer('dispose', null);

  @override
  Future<void> restartSession() => _answer('restartSession', null);

  @override
  Future<void> journeyRouteNetworkChanged() => _answer('journeyRouteNetworkChanged', null);

  @override
  Future<void> endJourney() => _answer('endJourney', null);
}

/// The SDK streams the map follows; every other member is unused.
class FakeSdk implements Proximiio {
  final states = StreamController<ProximiioState>.broadcast();
  final venueChanges = StreamController<VenueDataChange>.broadcast();

  @override
  Stream<ProximiioState> get stateChanges => states.stream;

  @override
  Stream<VenueDataChange> get venueDataChanges => venueChanges.stream;

  Future<void> close() async {
    await states.close();
    await venueChanges.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MapMsgStop _stop(String id, MapMsgStopState state) => MapMsgStop(
  id: id,
  title: id.toUpperCase(),
  coordinate: MapMsgCoordinate(latitude: 0, longitude: 0),
  kind: MapMsgStopKind.planned,
  state: state,
);

const _journey = Journey([JourneyStop(id: 'a', title: 'A', coordinate: Coordinate(latitude: 0, longitude: 0))]);

void main() {
  group('options', () {
    test('defaults map to the native defaults', () {
      final msg = toMsgOptions(const MapOptions());

      expect(msg.camera, MapMsgCameraMode.follow);
      expect(msg.floorSelector, MapMsgFloorSelector.none);
      expect(msg.trail, MapMsgTrailKind.off);
      expect(msg.features, MapMsgFeaturesKind.venueDefaults);
      expect(msg.insets, MapMsgInsetsKind.safeArea);
      expect(msg.insetValues, isNull);
      expect(msg.showsRoute, isTrue);
      expect(msg.backgroundColor, isNull, reason: 'keeps the transparent TextureView default on Android');
      expect(msg.chrome, isNull);
    });

    test('every setting is converted', () {
      final msg = toMsgOptions(
        MapOptions(
          camera: CameraMode.free,
          floorSelector: FloorSelectorPosition.trailing,
          trail: const MapTrail.lastFixes(40),
          features: const MapFeatures.only(MapLayerToggles(paths: false, baseTiles: false)),
          contentInsets: const MapContentInsets.safeAreaPlus(EdgeInsetsDirectional.only(bottom: 120, start: 8)),
          chrome: MapChrome.bare,
          routeLineStyle: const RouteLineStyle(color: Color(0xFF3F69FF), toColor: Color(0xFFED3731), width: 8),
          fallbackStyleUrl: Uri.parse('https://tiles.example.test/style.json'),
          language: 'ar',
          heading: HeadingMode.compass,
          backgroundColor: const Color(0x80FFFFFF),
        ),
      );

      expect(msg.camera, MapMsgCameraMode.free);
      expect(msg.floorSelector, MapMsgFloorSelector.trailing);
      expect(msg.trail, MapMsgTrailKind.lastFixes);
      expect(msg.trailValue, 40);
      expect(msg.features, MapMsgFeaturesKind.only);
      expect(msg.layerToggles?.paths, isFalse);
      expect(msg.layerToggles?.baseTiles, isFalse);
      expect(msg.layerToggles?.pois, isTrue);
      expect(msg.insets, MapMsgInsetsKind.safeAreaPlus);
      expect(msg.insetValues?.bottom, 120);
      expect(msg.insetValues?.leading, 8);
      expect(msg.chrome?.showsAttribution, isFalse);
      expect(msg.routeLineStyle?.color, 0xFF3F69FF);
      expect(msg.routeLineStyle?.toColor, 0xFFED3731);
      expect(msg.fallbackStyleUrl, 'https://tiles.example.test/style.json');
      expect(msg.language, 'ar');
      expect(msg.heading, MapMsgHeadingMode.compass);
      expect(msg.backgroundColor, 0x80FFFFFF);
    });

    test('options compare by value, so an unchanged rebuild does not resend them', () {
      expect(
        const MapOptions(floorSelector: FloorSelectorPosition.leading),
        const MapOptions(floorSelector: FloorSelectorPosition.leading),
      );
      expect(const MapOptions(), isNot(const MapOptions(camera: CameraMode.free)));
    });
  });

  group('journey models', () {
    test('JSON round trip', () {
      const journey = Journey([
        JourneyStop(id: 'a', title: 'Atrium', coordinate: Coordinate(latitude: 1, longitude: 2), level: 0),
        JourneyStop(
          id: 'b',
          title: 'Gallery',
          coordinate: Coordinate(latitude: 3, longitude: 4),
          kind: JourneyStopKind.detour,
          state: JourneyStopState.done,
        ),
      ]);

      expect(Journey.fromJson(journey.toJson()), journey);
    });

    test('a Map Editor journey becomes stops, waypoints without a position are left out', () {
      const proximiio = ProximiioJourney(
        id: 'tour',
        displayName: 'Tour',
        waypoints: [
          JourneyWaypoint(latitude: 1, longitude: 2, level: 1, label: 'Start'),
          JourneyWaypoint(label: 'No position'),
          JourneyWaypoint(latitude: 3, longitude: 4),
        ],
      );

      final journey = Journey.fromProximiioJourney(proximiio);

      expect(journey.stops.map((s) => s.id), ['tour-0', 'tour-2']);
      expect(journey.stops.first.title, 'Start');
      expect(journey.stops.last.title, 'Stop 3');
    });

    test('journey events by kind; unknown kinds do not throw', () {
      final stop = MapMsgStop(
        id: 's',
        title: 'S',
        coordinate: MapMsgCoordinate(latitude: 0, longitude: 0),
        kind: MapMsgStopKind.planned,
        state: MapMsgStopState.active,
      );

      expect(fromMsgNotice(MapMsgJourneyNotice(kind: 'stopReached', stop: stop)), isA<JourneyStopReached>());
      expect(
        fromMsgNotice(MapMsgJourneyNotice(kind: 'legChanged', stop: stop, reason: 'advanced')),
        isA<JourneyLegChanged>().having((e) => e.reason, 'reason', 'advanced'),
      );
      expect(
        fromMsgNotice(MapMsgJourneyNotice(kind: 'offRouteTooLong', durationSeconds: 90)),
        const JourneyOffRouteTooLong(Duration(seconds: 90)),
      );
      expect(fromMsgNotice(MapMsgJourneyNotice(kind: 'somethingNew')), const JourneyUnknownEvent('somethingNew'));
    });
  });

  group('controller', () {
    late FakeMapApi api;
    late StreamController<MapMsgEvent> events;

    setUp(() {
      api = FakeMapApi();
      events = StreamController<MapMsgEvent>.broadcast();
    });

    tearDown(() => events.close());

    test('map events update the listenable state', () async {
      final controller = createMapController(1, api: api, events: events.stream);
      final taps = <MapFeatureTap>[];
      final subscription = controller.featureTaps.listen(taps.add);

      events
        ..add(
          MapMsgFloorsChanged(
            floors: [
              MapMsgFloor(level: 0, name: 'Ground'),
              MapMsgFloor(level: 1),
            ],
          ),
        )
        ..add(MapMsgSelectedFloorChanged(level: 1, isPinned: true))
        ..add(MapMsgCameraModeChanged(mode: MapMsgCameraMode.free))
        ..add(MapMsgStyleSourceChanged(kind: MapMsgStyleSourceKind.organization))
        ..add(MapMsgErrorChanged(message: 'style failed'))
        ..add(MapMsgFeatureTapped(featureIds: ['poi-1'], coordinate: MapMsgCoordinate(latitude: 1, longitude: 2)))
        ..add(MapMsgCameraReady(isReady: true));
      await pumpEventQueue();

      expect(controller.floors.value, [const MapFloor(level: 0, name: 'Ground'), const MapFloor(level: 1)]);
      expect(controller.selectedFloor.value, const MapFloorSelection(level: 1, isPinned: true));
      expect(controller.cameraMode.value, CameraMode.free);
      expect(controller.styleSource.value, MapStyleSource.organization);
      expect(controller.lastError.value, 'style failed');
      expect(taps.single.featureIds, ['poi-1']);
      await expectLater(controller.cameraReady, completes);
      await subscription.cancel();
      await controller.dispose();
    });

    test('showRoute converts the route and keeps flutter_proximiio route options names', () async {
      final controller = createMapController(1, api: api, events: events.stream);

      final route = await controller.showRoute(
        from: const Coordinate(latitude: 1, longitude: 2),
        fromLevel: 0,
        to: const Coordinate(latitude: 1.0002, longitude: 2),
        toLevel: 1,
        options: const RouteOptions(profile: RouteProfile.wheelchair, avoid: {RouteAvoidance.revolvingDoors}),
      );

      expect(api.calls.single, 'showRoute(0.0→1.0 wheelchair [revolvingDoors])');
      expect(route.distanceMeters, 30);
      expect(route.segments, hasLength(1));
      expect(route.instructions.single.kind, RouteInstructionKind.arrive);
      expect(route.duration, const Duration(seconds: 25));
      await controller.dispose();
    });

    test('noRoute errors come back as ProximiioException, other errors as ProximiioMapException', () async {
      final controller = createMapController(1, api: api, events: events.stream);

      api.failWith = PlatformException(code: 'noRoute', details: {'reason': 'disconnected'});
      await expectLater(
        controller.showRoute(
          from: const Coordinate(latitude: 0, longitude: 0),
          fromLevel: 0,
          to: const Coordinate(latitude: 1, longitude: 1),
        ),
        throwsA(isA<ProximiioException>().having((e) => e.noRouteReason, 'reason', NoRouteReason.disconnected)),
      );

      api.failWith = PlatformException(code: 'notConfigured', message: 'no SDK');
      await expectLater(
        controller.selectFloor(1),
        throwsA(isA<ProximiioMapException>().having((e) => e.code, 'code', MapErrorCode.notConfigured)),
      );
      api.failWith = null;
      await controller.dispose();
    });

    test('calls after dispose fail as notReady', () async {
      final controller = createMapController(1, api: api, events: events.stream);
      await controller.dispose();

      expect(api.calls, ['dispose']);
      await expectLater(
        controller.selectFloor(0),
        throwsA(isA<ProximiioMapException>().having((e) => e.code, 'code', MapErrorCode.notReady)),
      );
    });

    test('a proposal is applied by its native id', () async {
      final controller = createMapController(
        1,
        api: api,
        events: events.stream,
        journeyEvents: () => const Stream.empty(),
      );
      final navigator = await controller.startJourney(
        const Journey([JourneyStop(id: 'a', title: 'A', coordinate: Coordinate(latitude: 0, longitude: 0))]),
        rules: const JourneyRules(advanceOnDepartureMeters: 8),
      );

      final proposal = await navigator.proposeOrder();

      expect(proposal?.savedMeters, 40);
      expect(proposal?.proposedDuration, const Duration(seconds: 50));
      expect(await navigator.apply(proposal!), isTrue);
      expect(api.calls, ['startJourney(1, 8.0)', 'proposeOrder', 'applyProposal(7)']);
      await controller.dispose();
    });

    test('the session is taken again only after the SDK was stopped and started', () async {
      final sdk = FakeSdk();
      final controller = createMapController(1, api: api, events: events.stream, sdk: () async => sdk);
      await pumpEventQueue();

      // A start() of a running SDK changes nothing.
      sdk.states.add(ProximiioState.running);
      await pumpEventQueue();
      expect(api.calls, isEmpty);

      sdk.states
        ..add(ProximiioState.authenticated)
        ..add(ProximiioState.running);
      await pumpEventQueue();
      expect(api.calls, ['restartSession']);

      api.failWith = PlatformException(code: 'notConfigured', message: 'rebuild the map');
      sdk.states
        ..add(ProximiioState.idle)
        ..add(ProximiioState.running);
      await pumpEventQueue();
      expect(controller.lastError.value, 'rebuild the map');
      await controller.dispose();
      await sdk.close();
    });

    test('a map that cannot be shown fails cameraReady instead of waiting', () async {
      final controller = createMapController(1, api: api, events: events.stream);
      events.addError(PlatformException(code: 'unsupported', message: 'needs Swift Package Manager'));

      await expectLater(
        controller.cameraReady,
        throwsA(isA<ProximiioMapException>().having((e) => e.code, 'code', MapErrorCode.unsupported)),
      );
      expect(controller.lastError.value, 'needs Swift Package Manager');
      await controller.dispose();
    });

    test('new features route the journey again; end() forgets the journey', () async {
      final sdk = FakeSdk();
      final controller = createMapController(
        1,
        api: api,
        events: events.stream,
        journeyEvents: () => const Stream.empty(),
        sdk: () async => sdk,
      );
      await pumpEventQueue();
      final navigator = await controller.startJourney(_journey);

      sdk.venueChanges
        ..add(const VenueDataChange({VenueDataKind.amenities}))
        ..add(const VenueDataChange({VenueDataKind.features}));
      await pumpEventQueue();
      expect(api.calls, ['startJourney(1, null)', 'journeyRouteNetworkChanged']);

      await navigator.end();
      expect(controller.journey, isNull);
      await expectLater(
        navigator.advance(),
        throwsA(isA<ProximiioMapException>().having((e) => e.code, 'code', MapErrorCode.noJourney)),
      );
      await controller.dispose();
      await sdk.close();
    });

    test('a paused listener holds neither the next journey nor dispose', () async {
      final journeyEvents = StreamController<MapMsgJourneyEvent>.broadcast();
      final controller = createMapController(
        1,
        api: api,
        events: events.stream,
        journeyEvents: () => journeyEvents.stream,
      );
      final first = await controller.startJourney(_journey);
      final subscription = first.events.listen((_) {})..pause();

      final second = await controller.startJourney(_journey).timeout(const Duration(seconds: 1));
      await controller.dispose().timeout(const Duration(seconds: 1));

      expect(identical(first, second), isFalse);
      expect(api.calls, ['startJourney(1, null)', 'startJourney(1, null)', 'dispose']);
      await subscription.cancel();
      await journeyEvents.close();
    });

    test('journeys start one after another', () async {
      final controller = createMapController(
        1,
        api: api,
        events: events.stream,
        journeyEvents: () => const Stream.empty(),
      );
      final starts = [controller.startJourney(_journey), controller.startJourney(_journey)];

      final navigators = await Future.wait(starts);
      expect(identical(controller.journey, navigators.last), isTrue);
      expect(api.calls, ['startJourney(1, null)', 'startJourney(1, null)']);
      await controller.dispose();
    });

    test('the journey state carries the stops a reorder may touch', () {
      final state = fromMsgJourneyState(
        MapMsgJourneyState(
          journey: MapMsgJourney(
            stops: [
              _stop('a', MapMsgStopState.done),
              _stop('b', MapMsgStopState.skipped),
              _stop('c', MapMsgStopState.active),
              _stop('d', MapMsgStopState.pending),
            ],
          ),
          overview: MapMsgOverview(
            remainingStopIds: const ['c', 'd'],
            legs: const [],
            remainingMeters: 0,
            etaSeconds: 0,
            unmeasuredLegCount: 0,
            unreachableStopIds: const [],
          ),
          hasArrived: false,
          isFinished: false,
          noRouteStopIds: const {},
          reorderableStopIds: const ['c', 'd'],
        ),
      );

      expect(state.reorderableStops.map((s) => s.id), ['c', 'd']);
    });
  });
}
