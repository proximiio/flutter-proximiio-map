import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_proximiio/flutter_proximiio.dart';
import 'package:flutter_proximiio_map/flutter_proximiio_map.dart';

/// The application token comes from the build, never from source:
///   cp env.example.json env.json   # put your token in env.json (gitignored)
///   flutter run --dart-define-from-file=env.json
const _token = String.fromEnvironment('PROXIMIIO_TOKEN');
const _apiBaseUrl = String.fromEnvironment('PROXIMIIO_API_BASE_URL');

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Proximi.io map',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF3F69FF)),
    home: const MapPage(),
  );
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  Proximiio? _sdk;
  ProximiioMapController? _map;
  JourneyNavigator? _journey;
  String _status = 'Starting…';

  @override
  void initState() {
    super.initState();
    if (_token.isNotEmpty) unawaited(_setUp());
  }

  Future<void> _setUp() async {
    try {
      final sdk = await Proximiio.create(
        ProximiioConfiguration(token: _token, apiBaseUrl: _apiBaseUrl.isEmpty ? null : Uri.parse(_apiBaseUrl)),
      );
      await sdk.requestPermissions();
      await sdk.authenticate();
      await sdk.loadCachedRouteNetwork();
      unawaited(sdk.loadRouteNetwork().then((_) {}, onError: (Object _) {}));
      await sdk.start();
      setState(() {
        _sdk = sdk;
        _status = 'Running';
      });
    } on ProximiioException catch (error) {
      setState(() => _status = '${error.code.name}: ${error.message ?? ''}');
    }
  }

  Future<void> _routeToFirstPoi() async {
    final sdk = _sdk;
    final map = _map;
    if (sdk == null || map == null) return;
    final position = await sdk.lastPosition();
    final pois = (await sdk.features()).where((f) => f.propertyType == 'poi' && f.geometry?['type'] == 'Point');
    if (position == null || pois.isEmpty) {
      setState(() => _status = position == null ? 'No position yet' : 'No POIs in the venue data');
      return;
    }
    final poi = pois.first;
    final coordinates = poi.geometry!['coordinates']! as List<Object?>;
    try {
      final route = await map.showRoute(
        from: position.coordinate,
        fromLevel: position.floor?.level ?? 0,
        to: Coordinate(latitude: (coordinates[1]! as num).toDouble(), longitude: (coordinates[0]! as num).toDouble()),
        toLevel: poi.level ?? 0,
      );
      await map.setGuidanceRules(RouteFollowRules.venueWalk);
      setState(() => _status = 'Route to ${poi.title() ?? poi.id}: ${route.distanceMeters.round()} m');
    } on ProximiioException catch (error) {
      setState(() => _status = 'No route: ${error.noRouteReason?.name ?? error.code.name}');
    }
  }

  Future<void> _startJourney() async {
    final sdk = _sdk;
    final map = _map;
    if (sdk == null || map == null) return;
    final journeys = await sdk.journeys();
    if (journeys.isEmpty) {
      setState(() => _status = 'No journeys in the Map Editor');
      return;
    }
    final navigator = await map.startJourney(
      Journey.fromProximiioJourney(journeys.first),
      rules: const JourneyRules(advanceOnDepartureMeters: 8),
    );
    navigator.events.listen((event) => setState(() => _status = '$event'));
    setState(() => _journey = navigator);
  }

  @override
  Widget build(BuildContext context) {
    final sdk = _sdk;
    return Scaffold(
      appBar: AppBar(title: const Text('Proximi.io map')),
      body:
          _token.isEmpty
              ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No token. Run with --dart-define-from-file=env.json (see env.example.json).'),
              )
              : Column(
                children: [
                  Expanded(
                    child:
                        sdk == null
                            ? Center(child: Text(_status))
                            : ProximiioMap(
                              options: const MapOptions(floorSelector: FloorSelectorPosition.trailing),
                              onMapCreated: (controller) => setState(() => _map = controller),
                            ),
                  ),
                  if (_map case final map?) _MapPanel(map: map, journey: _journey, status: _status),
                  if (_map != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(onPressed: () => _map?.recentre(), child: const Text('Recentre')),
                          OutlinedButton(onPressed: () => _map?.showVenue(), child: const Text('Venue')),
                          FilledButton.tonal(onPressed: _routeToFirstPoi, child: const Text('Route to a POI')),
                          FilledButton.tonal(onPressed: _startJourney, child: const Text('Journey')),
                        ],
                      ),
                    ),
                ],
              ),
    );
  }
}

class _MapPanel extends StatelessWidget {
  const _MapPanel({required this.map, required this.journey, required this.status});

  final ProximiioMapController map;
  final JourneyNavigator? journey;
  final String status;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder(
          valueListenable: map.selectedFloor,
          builder: (context, floor, _) => Text('Floor ${floor.level}${floor.isPinned ? ' (pinned)' : ''}'),
        ),
        ValueListenableBuilder(
          valueListenable: journey?.guidance ?? map.guidance,
          builder: (context, guidance, _) => Text(guidance?.text ?? status),
        ),
        ValueListenableBuilder(
          valueListenable: map.lastError,
          builder:
              (context, error, _) =>
                  error == null
                      ? const SizedBox.shrink()
                      : Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ],
    ),
  );
}
