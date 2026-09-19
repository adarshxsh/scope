package com.scope.attentions

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ComponentName
import android.content.Intent
import android.provider.Settings

/**
 * Main entry point for the Flutter Android app.
 *
 * Registers a MethodChannel ("com.scope.notifications") that the Flutter side
 * uses to:
 *   - Pull captured notifications from [NotificationCollectorService] using a two-phase transactional acknowledgment protocol
 *   - Acknowledge successfully stored notification IDs
 *   - Peek non-destructively at pending notifications
 *   - Query queue metrics
 *   - Check if the notification listener permission is granted
 *   - Open the system notification listener settings
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.scope.notifications"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSessionToken" -> {
                        result.success(NotificationCollectorService.getSessionToken())
                    }

                    "setSessionToken" -> {
                        val token = call.argument<String>("token")
                        if (token != null) {
                            NotificationCollectorService.setSessionToken(token)
                            result.success(true)
                        } else {
                            result.error("BAD_ARGS", "Missing token argument", null)
                        }
                    }

                    "getNotifications" -> {
                        val token = call.argument<String>("token") ?: call.argument<String>("sessionToken")
                        if (!NotificationCollectorService.validateToken(token)) {
                            result.error("UNAUTHORIZED", "Invalid session token", null)
                            return@setMethodCallHandler
                        }
                        val batch = NotificationCollectorService.getNotifications()
                        result.success(batch)
                    }

                    "acknowledgeNotifications" -> {
                        val token = call.argument<String>("token") ?: call.argument<String>("sessionToken")
                        if (!NotificationCollectorService.validateToken(token)) {
                            result.error("UNAUTHORIZED", "Invalid session token", null)
                            return@setMethodCallHandler
                        }
                        val ids = call.argument<List<String>>("notificationIds")
                            ?: call.argument<List<String>>("ids")
                            ?: emptyList()
                        val batchId = call.argument<String>("batchId")
                        val success = NotificationCollectorService.acknowledgeNotifications(ids, batchId)
                        result.success(success)
                    }

                    "peekNotifications" -> {
                        val token = call.argument<String>("token") ?: call.argument<String>("sessionToken")
                        if (!NotificationCollectorService.validateToken(token)) {
                            result.error("UNAUTHORIZED", "Invalid session token", null)
                            return@setMethodCallHandler
                        }
                        val notifications = NotificationCollectorService.peekNotifications()
                        val mapList = notifications.map { it.toMap() }
                        result.success(mapList)
                    }

                    "getQueueSize" -> {
                        val token = call.argument<String>("token") ?: call.argument<String>("sessionToken")
                        if (!NotificationCollectorService.validateToken(token)) {
                            result.error("UNAUTHORIZED", "Invalid session token", null)
                            return@setMethodCallHandler
                        }
                        val size = NotificationCollectorService.queueSize()
                        result.success(size)
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
