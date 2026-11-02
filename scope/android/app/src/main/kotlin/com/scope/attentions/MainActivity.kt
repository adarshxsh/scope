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
 *   - Pull captured notifications from [NotificationCollectorService]
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

                    "getIngestionGuardrails" -> {
                        NotificationCollectorService.ensureGuardrailsInitialized(this)
                        val guardrailsMap = NotificationCollectorService.getGuardrailsMap()
                        result.success(guardrailsMap)
                    }

                    "updateIngestionGuardrails" -> {
                        val args = call.arguments as? Map<*, *>
                        val blocked = (args?.get("blockedPackages") as? List<*>)?.filterIsInstance<String>()
                        val allowed = (args?.get("allowedPackages") as? List<*>)?.filterIsInstance<String>()
                        val whitelistMode = args?.get("isWhitelistMode") as? Boolean
                        val otp = args?.get("excludeOtp") as? Boolean
                        val finance = args?.get("excludeFinance") as? Boolean
                        val health = args?.get("excludeHealth") as? Boolean
                        val systemServices = args?.get("excludeSystemServices") as? Boolean

                        val updatedMap = NotificationCollectorService.updateGuardrails(
                            this, blocked, allowed, whitelistMode, otp, finance, health, systemServices
                        )
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
