package com.scope.attentions

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import java.security.SecureRandom
import java.security.MessageDigest

/**
 * Main entry point for the Flutter Android app.
 *
 * Registers a MethodChannel ("com.scope.notifications") that the Flutter side
 * uses to:
 *   - Pull captured notifications from [NotificationCollectorService]
 *   - Check if the notification listener permission is granted
 *   - Open the system notification listener settings
 *
 * Requires a 256-bit cryptographically secure session token generated during
 * Flutter engine initialization for all MethodChannel IPC calls.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.scope.notifications"
    }

    private var sessionToken: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        sessionToken = generateSecureToken()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSessionToken" -> {
                        result.success(sessionToken)
                    }

                    "getNotifications" -> {
                        val token = call.argument<String>("token")
                        if (!isValidToken(token)) {
                            result.error("SecurityException", "Invalid or missing session token", null)
                            return@setMethodCallHandler
                        }
                        val notifications = NotificationCollectorService.drainQueue()
                        val mapList = notifications.map { it.toMap() }
                        result.success(mapList)
                    }

                    "isListenerEnabled" -> {
                        val token = call.argument<String>("token")
                        if (!isValidToken(token)) {
                            result.error("SecurityException", "Invalid or missing session token", null)
                            return@setMethodCallHandler
                        }
                        val enabled = isNotificationListenerEnabled()
                        result.success(enabled)
                    }

                    "openNotificationSettings" -> {
                        val token = call.argument<String>("token")
                        if (!isValidToken(token)) {
                            result.error("SecurityException", "Invalid or missing session token", null)
                            return@setMethodCallHandler
                        }
                        openNotificationListenerSettings()
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun generateSecureToken(): String {
        val randomBytes = ByteArray(32)
        SecureRandom().nextBytes(randomBytes)
        return randomBytes.joinToString("") { "%02x".format(it) }
    }

    private fun isValidToken(token: String?): Boolean {
        val currentToken = sessionToken ?: return false
        if (token == null || token.length != currentToken.length) return false
        return MessageDigest.isEqual(token.toByteArray(Charsets.UTF_8), currentToken.toByteArray(Charsets.UTF_8))
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
