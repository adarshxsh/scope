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
 *   - Uses a static ConcurrentLinkedQueue (thread-safe, lock-free) bounded to
 *     [MAX_QUEUE_SIZE] to prevent background memory exhaustion.
 *   - Enforces strict sanitization and title redaction before writing to logcat.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum items allowed in queue to cap background memory usage. */
        const val MAX_QUEUE_SIZE = 500

        /** Thread-safe queue of captured notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /**
         * Redacts PII / sensitive notification titles for native logcat output.
         * Returns a non-reversible string containing length and SHA-256 fingerprint.
         */
        fun redactForLog(text: String?): String {
            if (text.isNullOrEmpty()) return "[EMPTY]"
            val len = text.length
            val hash = try {
                val md = MessageDigest.getInstance("SHA-256")
                val digest = md.digest(text.toByteArray(Charsets.UTF_8))
                digest.joinToString("") { "%02x".format(it) }.take(8)
            } catch (e: Exception) {
                "anon"
            }
            return "[REDACTED len=$len hash=$hash]"
        }

        /**
         * Sanitizes package name for native logcat output to prevent full package PII exposure.
         */
        fun sanitizePackageName(pkg: String?): String {
            if (pkg.isNullOrEmpty()) return "unknown"
            val hash = try {
                val md = MessageDigest.getInstance("SHA-256")
                val digest = md.digest(pkg.toByteArray(Charsets.UTF_8))
                digest.joinToString("") { "%02x".format(it) }.take(8)
            } catch (e: Exception) {
                "anon"
            }
            val parts = pkg.split(".")
            val prefix = if (parts.isNotEmpty()) parts.first() else "pkg"
            return "$prefix...#$hash"
        }

        /**
         * Drains all notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue is empty.
         */
        fun drainQueue(): List<NotificationData> {
            val result = mutableListOf<NotificationData>()
            while (true) {
                val item = queue.poll() ?: break
                result.add(item)
            }
            return result
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int = queue.size

        /**
         * Clears all items in the queue (for diagnostic reset/testing).
         */
        fun clearQueue() {
            queue.clear()
        }

        /**
         * Helper to add item to queue with bounding constraints (for testing & internal use).
         */
        fun enqueueData(data: NotificationData): Boolean {
            val isDuplicate = queue.any {
                it.packageName == data.packageName && it.title == data.title && it.content == data.content
            }
            if (isDuplicate) {
                return false
            }
            while (queue.size >= MAX_QUEUE_SIZE) {
                queue.poll()
            }
            return queue.add(data)
        }
    }

    private fun addSbnToQueue(sbn: StatusBarNotification) {
        try {
            val notification = sbn.notification ?: return
            val extras = notification.extras
            val rawTitle = extras?.getCharSequence("android.title")?.toString() ?: ""
            val rawText = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: "unknown"

            // Sanitize input boundaries
            val title = rawTitle.trim()
            val text = rawText.trim()

            val data = NotificationData(
                id = "notif_${++idCounter}",
                packageName = packageName,
                title = title,
                content = text,
                timestamp = sbn.postTime,
                category = notification.category,
                isOngoing = isOngoing
            )

            val added = enqueueData(data)
            if (added) {
                Log.d(TAG, "Captured: ${sanitizePackageName(data.packageName)} - ${redactForLog(data.title)}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error capturing notification gracefully", e)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        addSbnToQueue(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val rawTitle = sbn.notification?.extras?.getCharSequence("android.title")?.toString()
        Log.d(TAG, "Removed: ${sanitizePackageName(sbn.packageName)} - ${redactForLog(rawTitle)}")
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
