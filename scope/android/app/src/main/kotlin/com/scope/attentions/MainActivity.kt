package com.scope.attentions

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ComponentName
import android.content.Context
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
 *   - Synchronize package blacklist and category exclusion preferences
 *   - Query installed app package details
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.scope.notifications"
        private const val PREFS_NAME = "scope_privacy_settings"
        private const val KEY_BLACKLISTED_PACKAGES = "blacklisted_packages"
        private const val KEY_EXCLUDED_CATEGORIES = "excluded_categories"
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

                    "setPackageExclusionList" -> {
                        val packagesList = parseStringList(call.arguments, "packages")
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        prefs.edit().putStringSet(KEY_BLACKLISTED_PACKAGES, packagesList.toSet()).apply()
                        NotificationCollectorService.setPackageBlacklist(packagesList.toSet())
                        result.success(true)
                    }

                    "setCategoryExclusionRules" -> {
                        val categoriesList = parseStringList(call.arguments, "categories")
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        prefs.edit().putStringSet(KEY_EXCLUDED_CATEGORIES, categoriesList.toSet()).apply()
                        NotificationCollectorService.setCategoryExclusionRules(categoriesList.toSet())
                        result.success(true)
                    }

                    "getPackageExclusionList" -> {
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        val blacklisted = prefs.getStringSet(KEY_BLACKLISTED_PACKAGES, emptySet()) ?: emptySet()
                        result.success(blacklisted.toList())
                    }

                    "getCategoryExclusionRules" -> {
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        val excluded = prefs.getStringSet(KEY_EXCLUDED_CATEGORIES, emptySet()) ?: emptySet()
                        result.success(excluded.toList())
                    }

                    "getInstalledApps" -> {
                        val apps = getInstalledApps()
                        result.success(apps)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun parseStringList(args: Any?, mapKey: String): List<String> {
        return when (args) {
            is List<*> -> args.filterIsInstance<String>()
            is Map<*, *> -> (args[mapKey] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
            else -> emptyList()
        }
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val pm = packageManager
        val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolveInfos = pm.queryIntentActivities(mainIntent, 0)
        val appList = mutableListOf<Map<String, String>>()
        for (info in resolveInfos) {
            val appName = info.loadLabel(pm).toString()
            val pkgName = info.activityInfo.packageName
            appList.add(mapOf("appName" to appName, "packageName" to pkgName))
        }
        return appList.sortedBy { it["appName"]?.lowercase() ?: "" }
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

