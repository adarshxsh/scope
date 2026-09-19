package com.scope.attentions

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.content.ComponentName
import android.content.Intent
import android.provider.Settings

/**
 * Main entry point for the Flutter Android app.
 *
 * Registers a MethodChannel ("com.scope.notifications") and an EventChannel
 * ("com.scope.notifications/events") that the Flutter side uses to:
 *   - Push captured notification events from [NotificationCollectorService] in real-time
 *   - Pull captured notifications from [NotificationCollectorService] (startup synchronization)
 *   - Check if the notification listener permission is granted
 *   - Open the system notification listener settings
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.scope.notifications"
        private const val EVENT_CHANNEL = "com.scope.notifications/events"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNotifications" -> {
                        val notifications = NotificationCollectorService.drainQueue()
                        val mapList = notifications.map { it.toMap() }
                        result.success(mapList)
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

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    NotificationCollectorService.eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    NotificationCollectorService.eventSink = null
                }
            })
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
