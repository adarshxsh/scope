package com.scope.attentions

import android.content.ComponentName
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Main entry point for the Flutter Android app.
 *
 * Implements [EventChannel.StreamHandler] for "com.scope.notifications/stream"
 * to stream incoming notifications and active panel sync directly to Flutter.
 *
 * Registers a MethodChannel ("com.scope.notifications") for checking permissions
 * and opening system notification settings.
 */
class MainActivity : FlutterActivity(), EventChannel.StreamHandler {

    companion object {
        private const val CHANNEL = "com.scope.notifications"
        private const val STREAM_CHANNEL = "com.scope.notifications/stream"
    }

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STREAM_CHANNEL)
            .setStreamHandler(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    @Suppress("DEPRECATION")
                    "getNotifications" -> {
                        // Deprecated: MethodChannel polling is deprecated in favor of EventChannel streaming.
                        // Static queue removed; returns empty list.
                        result.success(emptyList<Map<String, Any?>>())
                    }

                    "isListenerEnabled" -> {
                        val enabled = isNotificationListenerEnabled()
                        result.success(enabled)
                    }

                    "openNotificationSettings" -> {
                        openNotificationListenerSettings()
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        NotificationCollectorService.listener = { data ->
            val map = data.toMap()
            mainHandler.post {
                eventSink?.success(map)
            }
        }
        // Direct active notification panel sync upon stream connection without queue retention
        NotificationCollectorService.syncActiveNotifications()
    }

    override fun onCancel(arguments: Any?) {
        NotificationCollectorService.listener = null
        eventSink = null
    }

    /**
     * Checks whether our NotificationListenerService has been granted access.
     */
    private fun isNotificationListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        ) ?: return false

        val componentName = ComponentName(this, NotificationCollectorService::class.java)
        return flat.contains(componentName.flattenToString())
    }

    /**
     * Opens the system Settings page where the user can enable notification access.
     */
    private fun openNotificationListenerSettings() {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        startActivity(intent)
    }
}

