package com.scope.attentions

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import java.util.concurrent.Executors

/**
 * Main entry point for the Flutter Android app.
 *
 * Registers MethodChannels:
 *   - "com.scope.notifications": For captured notification queries and permission settings.
 *   - "com.scope.keystore": For hardware-backed AndroidKeyStore key operations and secure database passphrases.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.scope.notifications"
        private const val KEYSTORE_CHANNEL = "com.scope.keystore"
    }

    private val bgExecutor = Executors.newSingleThreadExecutor()
    private val keyStoreHelper by lazy { KeyStoreHelper(applicationContext) }

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KEYSTORE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDatabasePassphrase" -> {
                        bgExecutor.execute {
                            try {
                                val passphrase = keyStoreHelper.getDatabasePassphrase()
                                runOnUiThread { result.success(passphrase) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("KEYSTORE_ERROR", e.message, null) }
                            }
                        }
                    }

                    "isStrongBoxSupported" -> {
                        bgExecutor.execute {
                            try {
                                val supported = keyStoreHelper.isStrongBoxSupported()
                                runOnUiThread { result.success(supported) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("KEYSTORE_ERROR", e.message, null) }
                            }
                        }
                    }

                    "isHardwareBacked" -> {
                        bgExecutor.execute {
                            try {
                                val hwBacked = keyStoreHelper.isHardwareBacked()
                                runOnUiThread { result.success(hwBacked) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("KEYSTORE_ERROR", e.message, null) }
                            }
                        }
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

    override fun onDestroy() {
        super.onDestroy()
        bgExecutor.shutdown()
    }
}
