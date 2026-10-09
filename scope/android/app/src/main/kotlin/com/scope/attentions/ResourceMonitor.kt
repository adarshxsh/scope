package com.scope.attentions

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import io.flutter.plugin.common.EventChannel

/**
 * Monitors system thermal status and battery level on Android.
 *
 * Streamed to Flutter over EventChannel ("com.scope.notifications/resource_state").
 */
class ResourceMonitor(private val context: Context) : EventChannel.StreamHandler {

    companion object {
        private const val TAG = "ResourceMonitor"
    }

    private var eventSink: EventChannel.EventSink? = null

    /** Thermal status code (0-6). Default: 0 (NONE). Set to -1 if unsupported. */
    var thermalStatus: Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) 0 else -1
        private set

    /** Battery level percentage (0-100). Default: 100. */
    var batteryLevel: Int = 100
        private set

    /** Charging state. Default: false. */
    var isCharging: Boolean = false
        private set

    private var thermalListener: PowerManager.OnThermalStatusChangedListener? = null
    private var isListening = false

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return
            updateBatteryState(intent)
            notifyResourceStateChanged()
        }
    }

    fun start() {
        if (isListening) return
        isListening = true

        // 1. Register Battery broadcast receiver
        try {
            val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val stickyIntent = context.registerReceiver(batteryReceiver, filter)
            stickyIntent?.let { updateBatteryState(it) }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register battery receiver", e)
        }

        // 2. Register Thermal Status Listener on Android 10+ (API 29+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                if (powerManager != null) {
                    val listener = PowerManager.OnThermalStatusChangedListener { status ->
                        thermalStatus = status
                        Log.d(TAG, "Thermal status changed: $status")
                        notifyResourceStateChanged()
                    }
                    powerManager.addThermalStatusListener(listener)
                    thermalListener = listener
                    thermalStatus = powerManager.currentThermalStatus
                }
            } catch (e: Exception) {
                Log.w(TAG, "Thermal status listener unavailable on this device", e)
                thermalStatus = -1
            }
        } else {
            thermalStatus = -1
        }
    }

    fun stop() {
        if (!isListening) return
        isListening = false

        try {
            context.unregisterReceiver(batteryReceiver)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to unregister battery receiver", e)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && thermalListener != null) {
            try {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                powerManager?.removeThermalStatusListener(thermalListener!!)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to remove thermal status listener", e)
            }
            thermalListener = null
        }
    }

    private fun updateBatteryState(intent: Intent) {
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level >= 0 && scale > 0) {
            batteryLevel = (level * 100) / scale
        }

        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL
    }

    fun getCurrentResourceMap(): Map<String, Any> {
        return mapOf(
            "thermalStatus" to thermalStatus,
            "batteryLevel" to batteryLevel,
            "isCharging" to isCharging
        )
    }

    private fun notifyResourceStateChanged() {
        eventSink?.success(getCurrentResourceMap())
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
        start()
        events?.success(getCurrentResourceMap())
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
    }
}
