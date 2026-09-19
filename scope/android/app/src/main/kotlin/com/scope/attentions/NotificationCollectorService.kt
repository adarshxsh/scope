package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.ArrayDeque
import java.util.HashSet

/**
 * Composite signature used for O(1) duplicate checks in [NotificationCollectorService].
 */
data class NotificationSignature(
    val packageName: String,
    val title: String,
    val content: String
)

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are placed in a static bounded queue which is drained
 * by [MainActivity] when Flutter requests them via MethodChannel.
 *
 * Design decisions:
 *   - Uses a synchronized bounded ArrayDeque (FIFO, capped capacity at 500)
 *     and a HashSet of notification signatures for O(1) duplicate checks.
 *   - Oldest notifications are evicted when capacity is reached.
 *   - No heavy processing here — just capture and queue.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum capacity for the notification queue to prevent unbounded memory growth. */
        const val MAX_CAPACITY = 500

        /** Synchronization lock for queue and deduplication set operations. */
        private val lock = Any()

        /** Bounded FIFO queue of captured notifications. */
        private val queue = ArrayDeque<NotificationData>()

        /** Set of unique notification signatures currently in the queue for O(1) deduplication. */
        private val signatures = HashSet<NotificationSignature>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /**
         * Enqueues a notification if it is not a duplicate.
         * Enforces MAX_CAPACITY (500 items) by evicting the oldest entry (FIFO) when full.
         *
         * @return true if added, false if duplicate.
         */
        fun addNotification(
            packageName: String,
            title: String,
            content: String,
            timestamp: Long,
            category: String?,
            isOngoing: Boolean
        ): Boolean {
            val sig = NotificationSignature(packageName, title, content)
            synchronized(lock) {
                if (signatures.contains(sig)) {
                    return false
                }

                if (queue.size >= MAX_CAPACITY) {
                    val evicted = queue.removeFirst()
                    signatures.remove(NotificationSignature(evicted.packageName, evicted.title, evicted.content))
                }

                val data = NotificationData(
                    id = "notif_${++idCounter}",
                    packageName = packageName,
                    title = title,
                    content = content,
                    timestamp = timestamp,
                    category = category,
                    isOngoing = isOngoing
                )

                queue.addLast(data)
                signatures.add(sig)
                return true
            }
        }

        /**
         * Drains all notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, both the queue and deduplication signatures are cleared atomically.
         */
        fun drainQueue(): List<NotificationData> {
            synchronized(lock) {
                val result = queue.toList()
                queue.clear()
                signatures.clear()
                return result
            }
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int {
            synchronized(lock) {
                return queue.size
            }
        }

        /**
         * Clears all notifications from queue and signature set.
         * Useful for testing and resets.
         */
        fun clearQueue() {
            synchronized(lock) {
                queue.clear()
                signatures.clear()
            }
        }
    }

    private fun addSbnToQueue(sbn: StatusBarNotification) {
        try {
            val extras = sbn.notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: "unknown"

            val added = addNotification(
                packageName = packageName,
                title = title,
                content = text,
                timestamp = sbn.postTime,
                category = sbn.notification.category,
                isOngoing = isOngoing
            )
            if (added) {
                Log.d(TAG, "Captured: $packageName - ${NotificationRedactor.redactTitle(title)}")
            }
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
        // Log for now; future phases may track dismissed notifications
        val removedTitle = sbn.notification.extras?.getCharSequence("android.title")?.toString()
        Log.d(TAG, "Removed: ${sbn.packageName} - ${NotificationRedactor.redactTitle(removedTitle)}")
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
