package com.scope.attentions

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.provider.Settings

/**
 * Main entry point for the Flutter Android app.
 *
 * Registers a MethodChannel ("com.scope.notifications") that the Flutter side
 * uses to:
 *   - Pull captured notifications from [NotificationCollectorService]
 *   - Check if the notification listener permission is granted
 *   - Open the system notification listener settings
 *   - Safely launch URLs and target app intents with security guardrails
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

                    "launchUrl" -> {
                        val url = call.argument<String>("url")
                        val success = launchUrlSafely(url)
                        result.success(success)
                    }

                    "launchApp" -> {
                        val packageName = call.argument<String>("packageName")
                        val success = launchAppSafely(packageName)
                        result.success(success)
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

    /**
     * Safely launches a web URL with scheme guardrails and browsable category.
     */
    private fun launchUrlSafely(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        try {
            val uri = Uri.parse(url)
            val scheme = uri.scheme?.lowercase() ?: return false
            if (scheme != "http" && scheme != "https" && scheme != "mailto" && scheme != "tel" && scheme != "sms") {
                return false
            }

            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (scheme == "http" || scheme == "https") {
                    addCategory(Intent.CATEGORY_BROWSABLE)
                }
            }

            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
                return true
            }
        } catch (e: Exception) {
            // Log or ignore safely
        }
        return false
    }

    /**
     * Safely launches an installed target app by package name.
     */
    private fun launchAppSafely(packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            }
        } catch (e: Exception) {
            // Log or ignore safely
        }
        return false
    }
}
