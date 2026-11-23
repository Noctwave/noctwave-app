package com.noctwave.noctwave_app

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Нативный BLE-рекламщик Android (ТЗ 5.2).
 *
 * Non-connectable BLE Advertising с ManufacturerData (0xFFF0),
 * 11-байтовый пейлоад prefix[8] + command[3]. Без GATT-подключения.
 * Геолокация не требуется: advertise-only на Android 10+ без сканирования.
 */
class BleAdvertiserPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL_NAME = "com.pulselocal/ble_advertiser"
        private const val MANUFACTURER_ID_DEFAULT = 0xFFF0
    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val handler = Handler(Looper.getMainLooper())
    private var advertiser: BluetoothLeAdvertiser? = null
    private var activeCallback: AdvertiseCallback? = null
    private var burstRunnable: Runnable? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopAdvertisingInternal()
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getBluetoothState" -> result.success(bluetoothState())
            "broadcastCommand" -> {
                val prefix = call.argument<String>("prefixHex") ?: ""
                val command = call.argument<String>("commandHex") ?: ""
                val manufacturerId = call.argument<Int>("manufacturerId") ?: MANUFACTURER_ID_DEFAULT
                val durationMs = call.argument<Int>("durationMs") ?: 350
                val ok = startAdvertising(prefix, command, manufacturerId, durationMs)
                if (ok) result.success(null)
                else result.error("ADVERTISE_FAILED", "Не удалось запустить BLE-рекламу", null)
            }
            "broadcastStop" -> {
                val prefix = call.argument<String>("prefixHex") ?: ""
                val stopHex = call.argument<String>("stopHex") ?: ""
                val manufacturerId = call.argument<Int>("manufacturerId") ?: MANUFACTURER_ID_DEFAULT
                val durationMs = call.argument<Int>("durationMs") ?: 700
                val ok = startAdvertising(prefix, stopHex, manufacturerId, durationMs)
                if (ok) result.success(null)
                else result.error("ADVERTISE_FAILED", "Не удалось отправить стоп-пакет", null)
            }
            "stopAdvertising" -> {
                stopAdvertisingInternal()
                result.success(null)
            }
            "previewEncodedPacket" -> {
                val prefix = call.argument<String>("prefixHex") ?: ""
                val command = call.argument<String>("commandHex") ?: ""
                val payload = hexToBytes(prefix) + hexToBytes(command)
                result.success(
                    mapOf(
                        "platform" to "android",
                        "rawHex" to bytesToHex(payload),
                        "manufacturerId" to MANUFACTURER_ID_DEFAULT,
                        "manufacturerDataHex" to bytesToHex(payload)
                    )
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun bluetoothState(): String {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            ?: return "unsupported"
        val adapter = manager.adapter ?: return "unsupported"
        if (!adapter.isEnabled) return "poweredOff"
        if (!hasAdvertisePermission()) return "unauthorized"
        return "ready"
    }

    private fun hasAdvertisePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.BLUETOOTH_ADVERTISE
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true // BLUETOOTH_ADMIN в манифесте, maxSdkVersion 30
        }
    }

    private fun startAdvertising(
        prefixHex: String,
        commandHex: String,
        manufacturerId: Int,
        durationMs: Int
    ): Boolean {
        stopAdvertisingInternal()

        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            ?: return false
        val adapter = manager.adapter ?: return false
        if (!adapter.isEnabled || !hasAdvertisePermission()) return false

        val bleAdvertiser = adapter.bluetoothLeAdvertiser ?: return false
        advertiser = bleAdvertiser

        val payload = hexToBytes(prefixHex) + hexToBytes(commandHex)
        if (payload.size != 11) return false

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false)
            .setTimeout(0) // остановка управляется таймером движка
            .build()

        // Строго без deviceName и TxPowerLevel — иначе смещаются байты (ТЗ 5.2).
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addManufacturerData(manufacturerId, payload)
            .build()

        val callback = object : AdvertiseCallback() {
            override fun onStartFailure(errorCode: Int) {
                stopAdvertisingInternal()
            }
        }
        activeCallback = callback

        return try {
            bleAdvertiser.startAdvertising(settings, data, callback)
            if (durationMs > 0) {
                val runnable = Runnable { stopAdvertisingInternal() }
                burstRunnable = runnable
                handler.postDelayed(runnable, durationMs.toLong())
            }
            true
        } catch (e: SecurityException) {
            false
        } catch (e: IllegalStateException) {
            false
        }
    }

    private fun stopAdvertisingInternal() {
        burstRunnable?.let { handler.removeCallbacks(it) }
        burstRunnable = null
        val callback = activeCallback
        val bleAdvertiser = advertiser
        if (callback != null && bleAdvertiser != null) {
            try {
                bleAdvertiser.stopAdvertising(callback)
            } catch (_: SecurityException) {
            } catch (_: IllegalStateException) {
            }
        }
        activeCallback = null
        advertiser = null
    }

    private fun hexToBytes(hex: String): ByteArray {
        val clean = hex.filter { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' }
        val out = ByteArray(clean.length / 2)
        for (i in out.indices) {
            out[i] = clean.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
        return out
    }

    private fun bytesToHex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02X".format(it) }
}
