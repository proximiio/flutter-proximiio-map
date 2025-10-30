# Flutter Proximiio Map

Flutter plugin for displaying Proximiio maps with real-time positioning using WebView integration.

## Features

- **Interactive Maps**: Display Proximiio maps in your Flutter application
- **Real-time Position Updates**: Show user location on the map in real-time
- **WebView Integration**: Seamless integration with Proximiio web maps
- **Event Handling**: Handle map clicks, feature clicks, and more
- **Customizable**: Configure map defaults (zoom, position, pitch, bearing)
- **Cross-Platform**: Works on both iOS and Android

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_proximiio_map:
    path: ../flutter_proximiio_map
```

Or from git:

```yaml
dependencies:
  flutter_proximiio_map:
    git:
      url: https://github.com/proximiio/flutter-proximiio-map
```

Then run:

```bash
flutter pub get
```

## Requirements

- `flutter_proximiio` plugin (for position updates)
- `webview_flutter` ^4.0.0
- Internet connection (maps are loaded from Proximiio servers)

## Usage

### Basic Map Display

```dart
import 'package:flutter_proximiio_map/flutter_proximiio_map.dart';

ProximiioMapWidget(
  token: 'your-proximiio-token',
  onMapReady: () {
    print('Map is ready!');
  },
)
```

### With Custom Map Defaults

```dart
ProximiioMapWidget(
  token: 'your-proximiio-token',
  mapDefaults: {
    'lat': 48.1486,
    'lng': 17.1077,
    'zoom': 18,
    'pitch': 0,
    'bearing': 0,
  },
  onMapReady: () {
    print('Map is ready!');
  },
)
```

### With Event Handlers

```dart
ProximiioMapWidget(
  token: 'your-proximiio-token',
  mapDefaults: {
    'lat': currentLocation.lat,
    'lng': currentLocation.lng,
    'zoom': 18,
  },
  onMapReady: () {
    debugPrint('Map is ready!');
  },
  onMapClick: (data) {
    debugPrint('Map clicked at: ${data['lngLat']}');
  },
  onFeatureClick: (data) {
    debugPrint('Feature clicked: ${data['title']}');
    // Show feature details to user
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(data['title'] ?? 'Feature'),
        content: Text('Feature ID: ${data['id']}'),
      ),
    );
  },
)
```

### With Real-time Position Updates

```dart
import 'package:flutter_proximiio/flutter_proximiio.dart';
import 'package:flutter_proximiio_map/flutter_proximiio_map.dart';

class MapScreen extends StatefulWidget {
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  ProximiioLocation _location = ProximiioLocation(lat: 0, lng: 0, sourceType: '');

  @override
  void initState() {
    super.initState();

    // Subscribe to position updates
    FlutterProximiio.subscribe(
      ProximiioEvents.positionUpdated,
      (ProximiioLocation location) {
        setState(() {
          _location = location;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ProximiioMapWidget(
      token: 'your-proximiio-token',
      mapDefaults: {
        'lat': _location.lat != 0 ? _location.lat : 48.1486,
        'lng': _location.lng != 0 ? _location.lng : 17.1077,
        'zoom': 18,
      },
      onMapReady: () {
        print('Map ready with position: ${_location.lat}, ${_location.lng}');
      },
      onFeatureClick: (data) {
        print('Clicked feature: ${data['title']}');
      },
    );
  }
}
```

## API Reference

### ProximiioMapWidget

Main widget for displaying Proximiio maps.

#### Constructor Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `token` | String | Yes | Your Proximiio API token |
| `mapDefaults` | Map<String, dynamic>? | No | Default map configuration (lat, lng, zoom, pitch, bearing) |
| `onMapReady` | void Function()? | No | Callback when map is fully loaded |
| `onMapClick` | void Function(Map<String, dynamic>)? | No | Callback when map is clicked |
| `onFeatureClick` | void Function(Map<String, dynamic>)? | No | Callback when a map feature is clicked |

#### mapDefaults Options

```dart
{
  'lat': 48.1486,           // Initial latitude
  'lng': 17.1077,           // Initial longitude
  'zoom': 18,               // Zoom level (0-22)
  'pitch': 0,               // Map pitch/tilt angle (0-60)
  'bearing': 0,             // Map rotation in degrees (0-360)
}
```

## How It Works

The plugin uses a WebView to load Proximiio web maps and establishes bidirectional communication:

1. **Flutter → WebView**: Position updates and commands are sent to the map
2. **WebView → Flutter**: Map events (clicks, feature clicks) are sent back to Flutter

The plugin automatically:
- Subscribes to position updates from `flutter_proximiio`
- Updates the map when position changes
- Forwards map events back to your Flutter app

## Platform Setup

### iOS

Add internet access permission to `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

### Android

Internet permission is already included in the plugin's AndroidManifest.xml.

## Example

See the [example application](../proximiio_flutter_example) for a complete working implementation showing:
- Map initialization
- Real-time position updates
- Feature click handling
- Tab-based navigation with data and map views

## Troubleshooting

### Map Not Loading

If the map doesn't load:

1. **Check internet connection**: Maps are loaded from Proximiio servers
2. **Verify token**: Ensure your Proximiio token is valid and has map access
3. **Check logs**: Look for WebView errors in the console
4. **Test on device**: WebView works better on physical devices than simulators

### Position Not Updating

If position doesn't update on the map:

1. **Check Proximiio plugin**: Ensure `flutter_proximiio` is properly initialized
2. **Verify subscriptions**: Make sure you're subscribed to position updates
3. **Check location permissions**: Ensure location permissions are granted
4. **Look at data flow**: Enable debug logging to see position updates

### WebView Issues

If you encounter WebView issues:

**iOS:**
```bash
cd ios
pod install
cd ..
flutter clean
flutter pub get
```

**Android:**
- Make sure you have the latest `webview_flutter` dependency
- Check that minSdkVersion is at least 21

### Map Shows Wrong Location

If the map shows the wrong location:

1. Update `mapDefaults` with correct coordinates
2. Ensure position updates are being received
3. Check that coordinates are in the correct format (decimal degrees)

## Dependencies

This plugin depends on:

- `flutter_proximiio`: Core Proximiio SDK integration
- `webview_flutter`: ^4.0.0 (WebView component)

## Technical Details

### Architecture

```
Flutter App
    ↓
ProximiioMapWidget
    ↓
WebViewController
    ↓
WebView (with HTML + iframe)
    ↓
Proximiio Web Map (maps.proximi.io)
```

### Communication Flow

```
Position Update → Flutter → WebView → Map (updates marker)
Map Event → WebView → Flutter → Callback (e.g., onFeatureClick)
```

### WebView Integration

The plugin uses an iframe-based approach:
1. Loads an HTML wrapper with an iframe pointing to Proximiio maps
2. Sets up bidirectional postMessage communication
3. Forwards position updates to the map
4. Relays map events back to Flutter

## Performance

- WebView runs on a separate thread
- Position updates are throttled to avoid overwhelming the map
- Map rendering is handled by the Proximiio web map (optimized)

## Security

- Always use HTTPS for map URLs
- Protect your Proximiio token (don't commit it to public repos)
- The plugin only communicates with Proximiio servers

## Limitations

- Requires internet connection
- WebView performance varies by platform
- Some map features may not work on all devices
- Limited offline support (maps must be loaded at least once)

## Learn More

- [Flutter Proximiio Plugin](../flutter_proximiio/README.md)
- [Example Application](../proximiio_flutter_example/README.md)
- [Proximiio Documentation](https://docs.proximi.fi)
- [Proximiio Web Maps](https://maps.proximi.io)

## Support

For issues and questions:
- GitHub: https://github.com/proximiio/flutter-proximiio-map
- Proximiio Support: https://proximi.fi/support

## License

MIT
