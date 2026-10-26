import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'convert.dart';
import 'messages.g.dart' as msg;
import 'options.dart';

/// Random per Dart isolate. A hot restart starts a new isolate, and the first map it prepares
/// releases the native maps of the old one.
final _isolateToken = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

/// The Proximi.io venue map: the native iOS or Android Map v6 as a platform view.
///
/// It shows the SDK instance made by `Proximiio.create` (create it first) with the visitor's
/// position, floors, routes and guidance. Control it through the [ProximiioMapController] passed
/// to [onMapCreated].
class ProximiioMap extends StatefulWidget {
  /// Creates a map.
  const ProximiioMap({
    super.key,
    this.options = const MapOptions(),
    this.onMapCreated,
    this.gestureRecognizers,
    this.placeholder = const SizedBox.expand(),
  });

  /// How the map looks and behaves. A changed value is sent to the map, also one set before the
  /// platform view exists; [MapOptions.offlinePackageId] and [MapOptions.initialFraming] apply only to a
  /// new map.
  final MapOptions options;

  /// Called once with the controller, when the native map exists.
  final void Function(ProximiioMapController controller)? onMapCreated;

  /// Gestures the map takes before Flutter widgets around it. By default it takes every gesture,
  /// so panning works inside scroll views.
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  /// Shown until the platform view is created.
  final Widget placeholder;

  @override
  State<ProximiioMap> createState() => _ProximiioMapState();
}

class _ProximiioMapState extends State<ProximiioMap> {
  static const _viewType = 'proximiio_map';
  int? _handle;
  ProximiioMapController? _controller;

  /// The options the native map has; a later [ProximiioMap.options] is sent once the view exists.
  MapOptions? _sentOptions;
  Object? _prepareError;

  static bool get _supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  Set<Factory<OneSequenceGestureRecognizer>> get _gestures =>
      widget.gestureRecognizers ?? {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)};

  @override
  void initState() {
    super.initState();
    if (_supported) _prepare();
  }

  Future<void> _prepare() async {
    final options = widget.options;
    final int handle;
    try {
      handle = await msg.MapRegistryApi().prepare(toMsgOptions(options), _isolateToken);
    } on Object catch (error) {
      if (mounted) setState(() => _prepareError = error);
      return;
    }
    if (!mounted) {
      msg.MapRegistryApi().release(handle).ignore();
      return;
    }
    setState(() {
      _handle = handle;
      _sentOptions = options;
    });
  }

  void _onPlatformViewCreated(int _) {
    final handle = _handle;
    if (handle == null || _controller != null || !mounted) return;
    final controller = createMapController(handle);
    _controller = controller;
    _sendOptions();
    widget.onMapCreated?.call(controller);
  }

  void _sendOptions() {
    final controller = _controller;
    if (controller == null || widget.options == _sentOptions) return;
    _sentOptions = widget.options;
    controller.setOptions(widget.options).ignore();
  }

  @override
  void didUpdateWidget(ProximiioMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sendOptions();
  }

  @override
  void dispose() {
    final controller = _controller;
    final handle = _handle;
    if (controller != null) {
      controller.dispose().ignore();
    } else if (handle != null) {
      // The platform view was never created (or not reported): only the registry knows the map.
      msg.MapRegistryApi().release(handle).ignore();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const Center(child: Text('The Proximi.io map runs on iOS and Android.'));
    final error = _prepareError;
    if (error != null) return Center(child: Text('The map could not be prepared: $error'));
    final handle = _handle;
    if (handle == null) return widget.placeholder;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => UiKitView(
        viewType: _viewType,
        creationParams: handle,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: _gestures,
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
      // The map renders to a TextureView by default, so texture-layer composition applies.
      TargetPlatform.android => AndroidView(
        viewType: _viewType,
        creationParams: handle,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: _gestures,
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}
