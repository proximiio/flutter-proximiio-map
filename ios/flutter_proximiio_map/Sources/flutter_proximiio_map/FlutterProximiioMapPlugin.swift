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

/// Options prepared by Dart, waiting for their platform view.
final class MapRegistry: MapRegistryApi {
  let messenger: FlutterBinaryMessenger
  private var pending: [Int64: MapMsgOptions] = [:]
  private var nextHandle: Int64 = 1

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func prepare(options: MapMsgOptions) throws -> Int64 {
    let handle = nextHandle
    nextHandle += 1
    pending[handle] = options
    return handle
  }

  func take(_ handle: Int64) -> MapMsgOptions? {
    pending.removeValue(forKey: handle)
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
    let options = registry.take(handle)
    #if canImport(ProximiioMap)
    guard let options else {
      return NoticeView(handle: handle, messenger: registry.messenger, text: "Map options missing.")
    }
    guard let sdk = MainActor.assumeIsolated({ Proximiio.shared }) else {
      return NoticeView(
        handle: handle,
        messenger: registry.messenger,
        text: "Call Proximiio.create(...) before showing the map.",
        code: "notConfigured"
      )
    }
    return MainActor.assumeIsolated {
      MapController(handle: handle, options: MapMappers.options(options), sdk: sdk, messenger: registry.messenger)
    }
    #else
    _ = options
    return NoticeView(
      handle: handle,
      messenger: registry.messenger,
      text: "flutter_proximiio_map needs Flutter's Swift Package Manager support on iOS."
    )
    #endif
  }
}

/// Shown when no map can be built; answers every call with an error.
final class NoticeView: NSObject, FlutterPlatformView {
  private let label = UILabel()

  init(handle: Int64, messenger: FlutterBinaryMessenger, text: String, code: String = "unsupported") {
    super.init()
    label.text = text
    label.numberOfLines = 0
    label.textAlignment = .center
    label.textColor = .secondaryLabel
    MapHostApiSetup.setUp(
      binaryMessenger: messenger,
      api: UnavailableMapApi(error: MapFlutterError(code: code, message: text, details: nil)),
      messageChannelSuffix: String(handle)
    )
  }

  func view() -> UIView { label }
}
