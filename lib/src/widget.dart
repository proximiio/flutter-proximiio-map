import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'convert.dart';
import 'messages.g.dart' as msg;
import 'options.dart';

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

  /// How the map looks and behaves. Changing it updates the map.
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

  Set<Factory<OneSequenceGestureRecognizer>> get _gestures =>
      widget.gestureRecognizers ?? {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)};

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final handle = await msg.MapRegistryApi().prepare(toMsgOptions(widget.options));
    if (!mounted) return;
    setState(() => _handle = handle);
  }

  void _onPlatformViewCreated(int _) {
    final handle = _handle;
    if (handle == null || _controller != null) return;
    final controller = createMapController(handle);
    _controller = controller;
    widget.onMapCreated?.call(controller);
  }

  @override
  void didUpdateWidget(ProximiioMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options != widget.options) {
      _controller?.setOptions(widget.options).ignore();
    }
  }

  @override
  void dispose() {
    _controller?.dispose().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      _ => const Center(child: Text('The Proximi.io map runs on iOS and Android.')),
    };
  }
}
