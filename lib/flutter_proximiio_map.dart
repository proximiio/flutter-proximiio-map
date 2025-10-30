library flutter_proximiio_map;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_proximiio/flutter_proximiio.dart';

class ProximiioMapWidget extends StatefulWidget {
  final String token;
  final Map<String, dynamic>? mapDefaults;
  final void Function()? onMapReady;
  final void Function(Map<String, dynamic>)? onMapClick;
  final void Function(Map<String, dynamic>)? onFeatureClick;

  const ProximiioMapWidget({
    super.key,
    required this.token,
    this.mapDefaults,
    this.onMapReady,
    this.onMapClick,
    this.onFeatureClick,
  });

  @override
  State<ProximiioMapWidget> createState() => _ProximiioMapWidgetState();
}

class _ProximiioMapWidgetState extends State<ProximiioMapWidget> {
  late final WebViewController _controller;
  bool _isReady = false;
  int _requestId = 0;
  final Map<int, Completer<dynamic>> _pendingCallbacks = {};

  // Subscription handlers
  StreamSubscription? _positionSubscription;
  StreamSubscription? _floorSubscription;

  // Track current location and floor
  double? _currentLat;
  double? _currentLng;
  int _currentLevel = 0;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _subscribeToProximiioEvents();
  }

  void _initializeWebView() {
    // Use the simple customer map URL
    final html = '''
<!DOCTYPE html>
<html style="height: 100%; margin: 0; padding: 0;">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <meta name="mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <style>
        html, body, iframe {
            height: 100%;
            width: 100%;
            margin: 0;
            padding: 0;
            border: 0;
            overflow: hidden;
        }
    </style>
</head>
<body>
    <iframe id="map-iframe" src="https://maps.proximi.io/<customer>/" style="height: 100%; width: 100%; border: 0;"></iframe>
    <script>
        // Listen for messages from Flutter
        window.addEventListener('message', function(event) {
          const iframe = document.getElementById('map-iframe');
          if (iframe && iframe.contentWindow) {
            iframe.contentWindow.postMessage(event.data, '*');
          }
        });

        // Forward messages from iframe to Flutter
        window.addEventListener('message', function(event) {
          if (event.source !== window) {
            // This message came from the iframe, forward to Flutter
            if (window.ProximiioMapChannel) {
              window.ProximiioMapChannel.postMessage(JSON.stringify(event.data));
            }
          }
        });
    </script>
</body>
</html>
    ''';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            debugPrint('Page finished loading: $url');
            _markAsReady();
          },
        ),
      )
      ..addJavaScriptChannel(
        'ProximiioMapChannel',
        onMessageReceived: (JavaScriptMessage message) {
          _handleJavaScriptMessage(message.message);
        },
      )
      ..loadHtmlString(html, baseUrl: 'https://maps.proximi.io');
  }

  void _subscribeToProximiioEvents() {
    // Subscribe to position updates
    FlutterProximiio.subscribe(
      ProximiioEvents.positionUpdated,
      (ProximiioLocation location) {
        _currentLat = location.lat;
        _currentLng = location.lng;
        _sendLocationUpdate();
      },
    );

    // Subscribe to floor changes
    FlutterProximiio.subscribe(
      ProximiioEvents.floorChanged,
      (ProximiioFloor floor) {
        _currentLevel = floor.level;
        _sendLocationUpdate();
      },
    );
  }

  void _sendLocationUpdate() {
    if (!_isReady || _currentLat == null || _currentLng == null) {
      debugPrint('[Proximiio Map] Cannot send location update - map not ready or location unavailable');
      return;
    }

    final locationData = {
      "type": "SET_LOCATION",
      "latitude": _currentLat,
      "longitude": _currentLng,
      "level": _currentLevel,
      "accelAvailable": true,
      "isInMovement": true
    };

    final jsonString = jsonEncode(locationData);
    final script = "window.postMessage('$jsonString', '*');";

    debugPrint('[Proximiio Map] Sending location update: $jsonString');
    _controller.runJavaScript(script);
  }

  void _markAsReady() {
    // Mark as ready after a short delay to ensure map initialization
    Future.delayed(const Duration(milliseconds: 500), () {
      setState(() {
        _isReady = true;
      });
      widget.onMapReady?.call();
    });
  }

  void _handleJavaScriptMessage(String message) {
    try {
      debugPrint('[Proximiio Map] Received message from WebView: $message');
      final data = jsonDecode(message);
      final type = data['type'];
      final payload = data['payload'];

      switch (type) {
        case 'MAP_READY':
          debugPrint('[Proximiio Map] Map is ready');
          if (!_isReady) {
            setState(() {
              _isReady = true;
            });
            widget.onMapReady?.call();
          }
          break;

        case 'MAP_CLICK':
          debugPrint('[Proximiio Map] Map clicked: $payload');
          widget.onMapClick?.call(payload);
          break;

        case 'FEATURE_CLICK':
          debugPrint('[Proximiio Map] Feature clicked: $payload');
          widget.onFeatureClick?.call(payload);
          break;

        case 'CALLBACK':
          final requestId = data['requestId'];
          debugPrint('[Proximiio Map] Callback received for request $requestId');
          if (requestId != null && _pendingCallbacks.containsKey(requestId)) {
            final completer = _pendingCallbacks.remove(requestId);
            if (data['error'] != null) {
              debugPrint('[Proximiio Map] Callback error: ${data['error']}');
              completer?.completeError(data['error']);
            } else {
              debugPrint('[Proximiio Map] Callback success: $payload');
              completer?.complete(payload);
            }
          }
          break;

        default:
          debugPrint('[Proximiio Map] Unknown message type: $type');
      }
    } catch (e) {
      debugPrint('[Proximiio Map] Error handling JavaScript message: $e');
    }
  }

  void _postMessage(String type, Map<String, dynamic> payload, [int? requestId]) {
    if (!_isReady) {
      debugPrint('[Proximiio Map] Map not ready, message queued: $type');
      return;
    }

    final message = {
      'type': type,
      'payload': payload,
      if (requestId != null) 'requestId': requestId,
    };

    debugPrint('[Proximiio Map] Sending message to WebView: type=$type, requestId=$requestId, payload=$payload');

    final script = '''
      window.postMessage(${jsonEncode(message)}, '*');
    ''';

    _controller.runJavaScript(script);
  }

  Future<T?> _callMethod<T>(String method, Map<String, dynamic> params) async {
    final requestId = _requestId++;
    final completer = Completer<T>();
    _pendingCallbacks[requestId] = completer;

    _postMessage(method, params, requestId);

    try {
      return await completer.future.timeout(const Duration(seconds: 10));
    } catch (e) {
      _pendingCallbacks.remove(requestId);
      debugPrint('Method call timeout or error: $method - $e');
      return null;
    }
  }

  // Public API methods
  Future<void> setCenter(double latitude, double longitude, {double? zoom}) async {
    await _callMethod('setCenter', {
      'latitude': latitude,
      'longitude': longitude,
      if (zoom != null) 'zoom': zoom,
    });
  }

  Future<void> flyTo(double latitude, double longitude, {double? zoom, int? duration}) async {
    await _callMethod('flyTo', {
      'latitude': latitude,
      'longitude': longitude,
      if (zoom != null) 'zoom': zoom,
      if (duration != null) 'duration': duration,
    });
  }

  Future<void> setFloor(String floorId) async {
    await _callMethod('setFloor', {'floorId': floorId});
  }

  Future<void> setRoute({
    required double startLat,
    required double startLng,
    required double destLat,
    required double destLng,
    String? startFloorId,
    String? destFloorId,
  }) async {
    await _callMethod('setRoute', {
      'start': {
        'latitude': startLat,
        'longitude': startLng,
        if (startFloorId != null) 'floorId': startFloorId,
      },
      'destination': {
        'latitude': destLat,
        'longitude': destLng,
        if (destFloorId != null) 'floorId': destFloorId,
      },
    });
  }

  Future<void> clearRoute() async {
    await _callMethod('clearRoute', {});
  }

  Future<void> setUserLocation(double latitude, double longitude, {double? accuracy}) async {
    _postMessage('updateLocation', {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy ?? 0.0,
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _floorSubscription?.cancel();
    FlutterProximiio.unsubscribeAll(ProximiioEvents.positionUpdated);
    FlutterProximiio.unsubscribeAll(ProximiioEvents.floorChanged);

    // Complete any pending callbacks with error
    for (final completer in _pendingCallbacks.values) {
      if (!completer.isCompleted) {
        completer.completeError('Widget disposed');
      }
    }
    _pendingCallbacks.clear();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: WebViewWidget(controller: _controller),
    );
  }
}
