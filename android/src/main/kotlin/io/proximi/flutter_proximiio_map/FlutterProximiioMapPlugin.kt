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
import io.flutter.plugin.common.EventChannel
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

/**
 * Options prepared by Dart, waiting for their platform view, and the maps made from them.
 *
 * A map is released by Dart (`release`, or the controller's `dispose`), by Flutter (the platform
 * view's `dispose`), or by a `prepare` from a new Dart isolate after a hot restart.
 */
internal class MapRegistry(val messenger: BinaryMessenger) : MapRegistryApi {
  private val pending = mutableMapOf<Long, MapMsgOptions>()
  private val views = mutableMapOf<Long, PlatformView>()
  private var nextHandle = 1L
  private var isolateToken: String? = null

  /** The activity lifecycle the map views follow. */
  var lifecycle: Lifecycle? = null

  override fun prepare(options: MapMsgOptions, isolateToken: String): Long {
    if (isolateToken != this.isolateToken) {
      this.isolateToken = isolateToken
      pending.clear()
      views.values.toList().forEach { it.dispose() }
      views.clear()
    }
    val handle = nextHandle++
    pending[handle] = options
    return handle
  }

  override fun release(handle: Long) {
    pending.remove(handle)
    views.remove(handle)?.dispose()
  }

  fun take(handle: Long): MapMsgOptions? = pending.remove(handle)

  fun add(handle: Long, view: PlatformView) {
    views[handle] = view
  }

  /** Called by a map when it is disposed. */
  fun removed(handle: Long) {
    views.remove(handle)
  }
}

internal class MapViewFactory(private val registry: MapRegistry) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
  override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
    val handle = (args as? Number)?.toLong() ?: 0L
    val view = view(context, handle)
    registry.add(handle, view)
    return view
  }

  private fun view(context: Context, handle: Long): PlatformView {
    val options = registry.take(handle)
      ?: return NoticeView(context, handle, registry, "Map options missing.", "invalidArgument")
    val sdk = Proximiio.shared
      ?: return NoticeView(context, handle, registry, "Call Proximiio.create(...) before showing the map.", "notConfigured")
    return MapController(context, handle, MapMappers.options(options), sdk, registry, registry.lifecycle)
  }
}

/** The per-map event channels; released with the map, so they do not keep it alive. */
internal object MapChannels {
  fun release(messenger: BinaryMessenger, handle: Long) {
    for (name in listOf("mapEvents", "journeyEvents")) {
      EventChannel(messenger, "dev.flutter.pigeon.flutter_proximiio_map.MapEventApi.$name.$handle", MapMessagesPigeonMethodCodec)
        .setStreamHandler(null)
    }
    MapHostApi.setUp(messenger, null, handle.toString())
  }
}

/**
 * Shown when no map can be built. Every call fails with the notice's error, and the map's event
 * stream reports it once, so `cameraReady` fails instead of waiting.
 */
internal class NoticeView(
  context: Context,
  private val handle: Long,
  private val registry: MapRegistry,
  text: String,
  code: String,
) : PlatformView {
  private val label = TextView(context).apply {
    this.text = text
    gravity = Gravity.CENTER
  }
  private var disposed = false

  init {
    val suffix = handle.toString()
    MapHostApi.setUp(registry.messenger, UnavailableMapApi(MapFlutterError(code, text), ::dispose), suffix)
    MapEventsStreamHandler.register(
      registry.messenger,
      object : MapEventsStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<MapMsgEvent>) = sink.error(code, text, null)
      },
      suffix,
    )
    JourneyEventsStreamHandler.register(registry.messenger, object : JourneyEventsStreamHandler() {}, suffix)
  }

  override fun getView(): View = label

  override fun dispose() {
    if (disposed) return
    disposed = true
    MapChannels.release(registry.messenger, handle)
    registry.removed(handle)
  }
}
