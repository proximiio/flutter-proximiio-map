package io.proximi.flutter_proximiio_map

import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.HiddenLifecycleReference
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.proximi.sdk.Proximiio

/** Registers the `proximiio_map` platform view and the registry that prepares maps. */
class FlutterProximiioMapPlugin : FlutterPlugin, ActivityAware {
  private var registry: MapRegistry? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val registry = MapRegistry(binding.binaryMessenger)
    this.registry = registry
    MapRegistryApi.setUp(binding.binaryMessenger, registry)
    binding.platformViewRegistry.registerViewFactory("proximiio_map", MapViewFactory(registry))
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    MapRegistryApi.setUp(binding.binaryMessenger, null)
    registry = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    registry?.lifecycle = (binding.lifecycle as? HiddenLifecycleReference)?.lifecycle
  }

  override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

  override fun onDetachedFromActivity() {
    registry?.lifecycle = null
  }
}

/** Options prepared by Dart, waiting for their platform view. */
internal class MapRegistry(val messenger: BinaryMessenger) : MapRegistryApi {
  private val pending = mutableMapOf<Long, MapMsgOptions>()
  private var nextHandle = 1L

  /** The activity lifecycle the map views follow. */
  var lifecycle: Lifecycle? = null

  override fun prepare(options: MapMsgOptions): Long {
    val handle = nextHandle++
    pending[handle] = options
    return handle
  }

  fun take(handle: Long): MapMsgOptions? = pending.remove(handle)
}

internal class MapViewFactory(private val registry: MapRegistry) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
  override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
    val handle = (args as? Number)?.toLong() ?: 0L
    val options = registry.take(handle)
      ?: return NoticeView(context, handle, registry.messenger, "Map options missing.", "invalidArgument")
    val sdk = Proximiio.shared
      ?: return NoticeView(
        context,
        handle,
        registry.messenger,
        "Call Proximiio.create(...) before showing the map.",
        "notConfigured",
      )
    return MapController(context, handle, MapMappers.options(options), sdk, registry.messenger, registry.lifecycle)
  }
}

/** Shown when no map can be built; answers every call with an error. */
internal class NoticeView(
  context: Context,
  private val handle: Long,
  private val messenger: BinaryMessenger,
  text: String,
  code: String,
) : PlatformView {
  private val label = TextView(context).apply {
    this.text = text
    gravity = Gravity.CENTER
  }

  init {
    MapHostApi.setUp(messenger, UnavailableMapApi(MapFlutterError(code, text)), handle.toString())
  }

  override fun getView(): View = label

  override fun dispose() = MapHostApi.setUp(messenger, null, handle.toString())
}
