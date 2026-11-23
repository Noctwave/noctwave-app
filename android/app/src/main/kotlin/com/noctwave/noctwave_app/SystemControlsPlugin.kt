package com.noctwave.noctwave_app

import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Системные функции OLED-замка (ТЗ 3.2.4):
 * - setKeepScreenOn: FLAG_KEEP_SCREEN_ON на окне Activity;
 * - «Громкость вниз» → событие volumeDown в Dart (экстренный СТОП).
 *
 * KeyEvent перехватывается на уровне Activity через onKeyDown MainActivity.
 */
class SystemControlsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    companion object {
        private const val CHANNEL_NAME = "com.pulselocal/system_controls"
        var instance: SystemControlsPlugin? = null
    }

    private lateinit var channel: MethodChannel
    private var activity: android.app.Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        instance = this
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        instance = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setKeepScreenOn" -> {
                val enabled = call.arguments as? Boolean ?: false
                val act = activity
                if (act != null) {
                    act.runOnUiThread {
                        if (enabled) {
                            act.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            act.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    result.success(null)
                } else {
                    result.error("NO_ACTIVITY", "Activity недоступна", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Вызывается из MainActivity.onKeyDown при KEYCODE_VOLUME_DOWN. */
    fun notifyVolumeDown() {
        channel.invokeMethod("volumeDown", null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
