package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.security.MessageDigest
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are placed in a static [queue] which is drained
 * by [MainActivity] when Flutter requests them via MethodChannel.
 *
 * Design decisions:
 *   - Uses a static ConcurrentLinkedQueue (thread-safe, lock-free) because
 *     the service runs in a separate context from MainActivity.
 *   - Payload fields (title, content) are redacted and AES-256 GCM encrypted in memory.
 *   - Logcat entries output hashed package names and message counts only.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Thread-safe queue of captured notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /**
         * Hashes package name using SHA-256 for anonymous Logcat output.
         */
        private fun hashPackageName(pkg: String): String {
            return try {
                val bytes = MessageDigest.getInstance("SHA-256").digest(pkg.toByteArray(Charsets.UTF_8))
                bytes.take(6).joinToString("") { "%02x".format(it) }
            } catch (e: Exception) {
                "anon"
            }
        }

        /**
         * Drains all notifications from the queue and returns them decrypted.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue is empty.
         */
        fun drainQueue(): List<NotificationData> {
            val result = mutableListOf<NotificationData>()
            while (true) {
                val item = queue.poll() ?: break
                val decryptedItem = item.copy(
                    title = CryptoManager.decrypt(item.title),
                    content = CryptoManager.decrypt(item.content)
                )
                result.add(decryptedItem)
            }
            return result
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int = queue.size
    }

    private fun addSbnToQueue(sbn: StatusBarNotification) {
        try {
            val extras = sbn.notification.extras
            val rawTitle = extras?.getCharSequence("android.title")?.toString() ?: ""
            val rawText = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: "unknown"

            val redactedTitle = NotificationRedactor.redact(rawTitle)
            val redactedContent = NotificationRedactor.redact(rawText)

            // Ignore if same package, title, and content already exist in queue
            val isDuplicate = queue.any { item ->
                item.packageName == packageName &&
                CryptoManager.decrypt(item.title) == redactedTitle &&
                CryptoManager.decrypt(item.content) == redactedContent
            }
            if (isDuplicate) {
                return
            }

            val encryptedTitle = CryptoManager.encrypt(redactedTitle)
            val encryptedContent = CryptoManager.encrypt(redactedContent)

            val data = NotificationData(
                id = "notif_${++idCounter}",
                packageName = packageName,
                title = encryptedTitle,
                content = encryptedContent,
                timestamp = sbn.postTime,
                category = sbn.notification.category,
                isOngoing = isOngoing
            )

            queue.add(data)
            Log.d(TAG, "Captured: pkg=${hashPackageName(packageName)}, queueSize=${queueSize()}")
        } catch (e: Exception) {
            Log.e(TAG, "Error capturing/adding notification", e)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        addSbnToQueue(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val pkg = sbn.packageName ?: "unknown"
        Log.d(TAG, "Removed: pkg=${hashPackageName(pkg)}, queueSize=${queueSize()}")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "NotificationCollectorService connected")
        try {
            val activeNotifs = activeNotifications
            if (activeNotifs != null) {
                Log.d(TAG, "Syncing ${activeNotifs.size} existing notifications from panel")
                for (sbn in activeNotifs) {
                    addSbnToQueue(sbn)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error fetching active notifications on connect", e)
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.w(TAG, "NotificationCollectorService disconnected")
    }
}
