package com.scope.attentions

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import android.util.Log
import java.util.UUID

/**
 * Main entry point for the Flutter Android app.
 *
 * Registers a MethodChannel ("com.scope.notifications") that the Flutter side
 * uses to:
 *   - Authenticate the Flutter bridge via session token
 *   - Pull captured notifications from [NotificationCollectorService]
 *   - Check if the notification listener permission is granted
 *   - Open the system notification listener settings
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.scope.notifications"
        private const val TAG = "ScopeMainActivity"
        private const val MIN_DRAIN_INTERVAL_MS = 50L
    }

    private val sessionToken: String = UUID.randomUUID().toString()
    private var lastDrainTimestamp: Long = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAuthToken" -> {
                        Log.i(TAG, "Audit: Auth token issued to authorized Flutter engine.")
                        result.success(sessionToken)
                    }

                    "getNotifications" -> {
                        val token = call.argument<String>("authToken")
                        if (token == null || token != sessionToken) {
                            Log.w(TAG, "Audit: Unauthorized getNotifications call blocked [Invalid or missing token].")
                            result.error("UNAUTHORIZED", "Unauthorized: Invalid or missing authorization token", null)
                            return@setMethodCallHandler
                        }

                        val now = System.currentTimeMillis()
                        if (now - lastDrainTimestamp < MIN_DRAIN_INTERVAL_MS) {
                            Log.w(TAG, "Audit: Rate limit exceeded on getNotifications drain request.")
                            result.error("RATE_LIMITED", "Rate limit exceeded: Please space requests", null)
                            return@setMethodCallHandler
                        }
                        lastDrainTimestamp = now

                        val notifications = NotificationCollectorService.drainQueue()
                        val mapList = notifications.map { it.toMap() }
                        Log.i(TAG, "Audit: Drained ${mapList.size} notifications for authorized session.")
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
