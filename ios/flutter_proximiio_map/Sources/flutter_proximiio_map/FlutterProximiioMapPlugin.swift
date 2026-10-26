import Flutter
import UIKit
#if canImport(ProximiioMap)
import Proximiio
import ProximiioMap
#endif

/// Registers the `proximiio_map` platform view and the registry that prepares maps.
///
/// The Proximi.io map library ships only as a Swift package. Built through CocoaPods, the plugin
/// compiles without it and every map shows a notice instead (`unsupported` on every call).
public final class FlutterProximiioMapPlugin: NSObject, FlutterPlugin {
  private let registry: MapRegistry

  private init(messenger: FlutterBinaryMessenger) {
    registry = MapRegistry(messenger: messenger)
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = FlutterProximiioMapPlugin(messenger: registrar.messenger())
    MapRegistryApiSetup.setUp(binaryMessenger: registrar.messenger(), api: plugin.registry)
    registrar.register(MapViewFactory(registry: plugin.registry), withId: "proximiio_map")
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    MapRegistryApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
  }
}

/// A map the registry can release: a ``MapController`` or a ``NoticeView``.
protocol ReleasableMap: AnyObject {
  func releaseMap()
}

/// Options prepared by Dart, waiting for their platform view, and the maps made from them.
///
/// On iOS a platform view has no dispose callback, so a map is released only by Dart (`release`,
/// or the controller's `dispose`) or by a `prepare` from a new Dart isolate after a hot restart.
final class MapRegistry: MapRegistryApi {
  let messenger: FlutterBinaryMessenger
  private var pending: [Int64: MapMsgOptions] = [:]
  private var views: [Int64: ReleasableMap] = [:]
  private var nextHandle: Int64 = 1
  private var isolateToken: String?

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func prepare(options: MapMsgOptions, isolateToken: String) throws -> Int64 {
    if isolateToken != self.isolateToken {
      self.isolateToken = isolateToken
      pending.removeAll()
      let stale = Array(views.values)
      views.removeAll()
      stale.forEach { $0.releaseMap() }
    }
    let handle = nextHandle
    nextHandle += 1
    pending[handle] = options
    return handle
  }

  func release(handle: Int64) throws {
    pending[handle] = nil
    views.removeValue(forKey: handle)?.releaseMap()
  }

  func take(_ handle: Int64) -> MapMsgOptions? {
    pending.removeValue(forKey: handle)
  }

  func add(_ handle: Int64, _ view: ReleasableMap) {
    views[handle] = view
  }

  /// Called by a map when it is released.
  func removed(_ handle: Int64) {
    views[handle] = nil
  }
}

/// The per-map channels; released with the map, so they do not keep it alive.
enum MapChannels {
  static func release(messenger: FlutterBinaryMessenger, handle: Int64) {
    for name in ["mapEvents", "journeyEvents"] {
      FlutterEventChannel(
        name: "dev.flutter.pigeon.flutter_proximiio_map.MapEventApi.\(name).\(handle)",
        binaryMessenger: messenger,
        codec: mapMessagesPigeonMethodCodec
      ).setStreamHandler(nil)
    }
    MapHostApiSetup.setUp(binaryMessenger: messenger, api: nil, messageChannelSuffix: String(handle))
  }
}

final class MapViewFactory: NSObject, FlutterPlatformViewFactory {
  private let registry: MapRegistry

  init(registry: MapRegistry) {
    self.registry = registry
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let handle = (args as? NSNumber)?.int64Value ?? 0
    let view = makeView(handle)
    registry.add(handle, view)
    return view
  }

  private func makeView(_ handle: Int64) -> FlutterPlatformView & ReleasableMap {
    let options = registry.take(handle)
    #if canImport(ProximiioMap)
    guard let options else {
      return NoticeView(handle: handle, registry: registry, text: "Map options missing.", code: "invalidArgument")
    }
    guard let sdk = MainActor.assumeIsolated({ Proximiio.shared }) else {
      return NoticeView(
        handle: handle,
        registry: registry,
        text: "Call Proximiio.create(...) before showing the map.",
        code: "notConfigured"
      )
    }
    return MainActor.assumeIsolated {
      MapController(handle: handle, options: MapMappers.options(options), sdk: sdk, registry: registry)
    }
    #else
    _ = options
    return NoticeView(
      handle: handle,
      registry: registry,
      text: "flutter_proximiio_map needs Flutter's Swift Package Manager support on iOS."
    )
    #endif
  }
}

/// The map event stream of a notice: reports the notice's error once, so `cameraReady` fails
/// instead of waiting.
private final class NoticeEventsRelay: MapEventsStreamHandler {
  let error: MapFlutterError

  init(error: MapFlutterError) {
    self.error = error
  }

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<MapMsgEvent>) {
    sink.error(code: error.code, message: error.message, details: nil)
  }
}

/// Shown when no map can be built; answers every call with an error.
final class NoticeView: NSObject, FlutterPlatformView, ReleasableMap {
  private let label = UILabel()
  private let handle: Int64
  private weak var registry: MapRegistry?
  private let messenger: FlutterBinaryMessenger
  private var released = false

  init(handle: Int64, registry: MapRegistry, text: String, code: String = "unsupported") {
    self.handle = handle
    self.registry = registry
    messenger = registry.messenger
    super.init()
    label.text = text
    label.numberOfLines = 0
    label.textAlignment = .center
    label.textColor = .secondaryLabel
    let error = MapFlutterError(code: code, message: text, details: nil)
    let suffix = String(handle)
    MapHostApiSetup.setUp(
      binaryMessenger: messenger,
      api: UnavailableMapApi(error: error, onDispose: { [weak self] in self?.releaseMap() }),
      messageChannelSuffix: suffix
    )
    MapEventsStreamHandler.register(with: messenger, instanceName: suffix, streamHandler: NoticeEventsRelay(error: error))
    JourneyEventsStreamHandler.register(with: messenger, instanceName: suffix, streamHandler: JourneyEventsStreamHandler())
  }

  func view() -> UIView { label }

  func releaseMap() {
    guard !released else { return }
    released = true
    MapChannels.release(messenger: messenger, handle: handle)
    registry?.removed(handle)
  }
}
