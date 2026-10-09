package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.security.MessageDigest

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are redacted for sensitive PII/OTPs and placed in a
 * bounded static queue (capacity 100) which is drained by [MainActivity]
 * when Flutter requests them via MethodChannel.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotificationCollector"

        /** Maximum allowed queue size to prevent unbounded memory growth. */
        const val MAX_QUEUE_SIZE = 100

        /** Maximum time-to-live for queued notifications (15 minutes in milliseconds). */
        const val MAX_AGE_MS = 15 * 60 * 1000L

        /** Thread-safe bounded queue of captured notifications (capacity 100). */
        private val queue = BoundedNotificationQueue<NotificationData>(MAX_QUEUE_SIZE)

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /**
         * Computes a SHA-256 hash digest of package name for secure diagnostic logging.
         */
        private fun hashPackage(packageName: String): String {
            return try {
                val digest = MessageDigest.getInstance("SHA-256")
                val hashBytes = digest.digest(packageName.toByteArray(Charsets.UTF_8))
                hashBytes.joinToString("") { "%02x".format(it) }.take(8)
            } catch (e: Exception) {
                packageName.hashCode().toString()
            }
        }

        /**
         * Removes entries older than [MAX_AGE_MS] from the queue.
         */
        fun pruneExpired(now: Long = System.currentTimeMillis()) {
            queue.removeIf { now - it.timestamp > MAX_AGE_MS }
        }

        /**
         * Adds a [NotificationData] item to the queue after pruning expired items
         * and enforcing maximum queue capacity.
         */
        fun addNotification(data: NotificationData, now: Long = System.currentTimeMillis()) {
            pruneExpired(now)

            // Do not add item if it is already expired relative to current time
            if (now - data.timestamp > MAX_AGE_MS) {
                return
            }

            // Ignore if same package, title, and content already exist in queue
            val isDuplicate = queue.any {
                it.packageName == data.packageName && it.title == data.title && it.content == data.content
            }
            if (isDuplicate) {
                return
            }

            queue.add(data)
        }

        /**
         * Drains all non-expired notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue is empty.
         */
        fun drainQueue(now: Long = System.currentTimeMillis()): List<NotificationData> {
            val result = mutableListOf<NotificationData>()
            while (true) {
                val item = queue.poll() ?: break
                if (now - item.timestamp <= MAX_AGE_MS) {
                    result.add(item)
                }
            }
            return result
        }

        /**
         * Clears the queue and resets internal state (for testing).
         */
        fun clearQueue() {
            queue.clear()
            idCounter = 0L
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int = queue.size
    }

    private fun addSbnToQueue(sbn: StatusBarNotification, now: Long = System.currentTimeMillis()) {
        try {
            val extras = sbn.notification.extras
            val rawTitle = extras?.getCharSequence("android.title")?.toString() ?: ""
            val rawText = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: "unknown"
            val timestamp = if (sbn.postTime > 0) sbn.postTime else now

            // Redact PII and OTP sensitive patterns prior to memory queue insertion
            val title = NotificationRedactor.redact(rawTitle)
            val text = NotificationRedactor.redact(rawText)

            val data = NotificationData(
                id = "notif_${++idCounter}",
                packageName = packageName,
                title = title,
                content = text,
                timestamp = timestamp,
                category = sbn.notification.category,
                isOngoing = isOngoing
            )

            addNotification(data, now)
            Log.d(TAG, "Notification posted from package: ${hashPackage(packageName)}")
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
        Log.d(TAG, "Notification removed from package: ${hashPackage(sbn.packageName ?: "unknown")}")
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
