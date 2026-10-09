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

        /** Alias for MAX_CAPACITY for backwards compatibility. */
        const val MAX_QUEUE_SIZE = MAX_CAPACITY

        /** Maximum time-to-live for queued notifications (15 minutes in milliseconds). */
        const val MAX_AGE_MS = 15 * 60 * 1000L

        /** Synchronization lock for queue and deduplication set operations. */
        private val lock = Any()

        /** Bounded FIFO queue of captured notifications. */
        private val queue = ArrayDeque<NotificationData>()

        /** Set of unique notification signatures currently in the queue for O(1) deduplication. */
        private val signatures = HashSet<NotificationSignature>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /**
         * Removes entries older than [MAX_AGE_MS] from the queue and deduplication set.
         */
        fun pruneExpired(now: Long = System.currentTimeMillis()) {
            synchronized(lock) {
                val iterator = queue.iterator()
                while (iterator.hasNext()) {
                    val item = iterator.next()
                    if (now - item.timestamp > MAX_AGE_MS) {
                        iterator.remove()
                        signatures.remove(NotificationSignature(item.packageName, item.title, item.content))
                    }
                }
            }
        }

        /**
         * Adds a [NotificationData] item to the queue after pruning expired items
         * and enforcing maximum queue capacity.
         *
         * @return true if added, false if duplicate or expired.
         */
        fun addNotification(data: NotificationData, now: Long = data.timestamp): Boolean {
            synchronized(lock) {
                pruneExpired(now)

                // Do not add item if it is already expired relative to current time
                if (now - data.timestamp > MAX_AGE_MS) {
                    return false
                }

                val sig = NotificationSignature(data.packageName, data.title, data.content)
                if (signatures.contains(sig)) {
                    return false
                }

                // Evict oldest notification if queue reaches MAX_CAPACITY before adding new items
                while (queue.size >= MAX_CAPACITY) {
                    val evicted = queue.removeFirst()
                    signatures.remove(NotificationSignature(evicted.packageName, evicted.title, evicted.content))
                }

                queue.addLast(data)
                signatures.add(sig)
                return true
            }
        }

        /**
         * Enqueues a notification with individual field parameters if it is not a duplicate.
         * Enforces MAX_CAPACITY (500 items) by evicting the oldest entry (FIFO) when full.
         *
         * @return true if added, false if duplicate or expired.
         */
        fun addNotification(
            packageName: String,
            title: String,
            content: String,
            timestamp: Long,
            category: String?,
            isOngoing: Boolean,
            now: Long = timestamp
        ): Boolean {
            val data = NotificationData(
                id = "notif_${synchronized(lock) { ++idCounter }}",
                packageName = packageName,
                title = title,
                content = content,
                timestamp = timestamp,
                category = category,
                isOngoing = isOngoing
            )
            return addNotification(data, now)
        }

        /**
         * Drains all non-expired notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, both the queue and deduplication signatures are cleared atomically.
         */
        fun drainQueue(now: Long = System.currentTimeMillis()): List<NotificationData> {
            synchronized(lock) {
                pruneExpired(now)
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
         * Clears all notifications from queue and signature set, resetting internal state.
         * Useful for testing and resets.
         */
        fun clearQueue() {
            synchronized(lock) {
                queue.clear()
                signatures.clear()
                idCounter = 0L
            }
        }
    }

    private fun addSbnToQueue(sbn: StatusBarNotification, now: Long = System.currentTimeMillis()) {
        try {
            val extras = sbn.notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: "unknown"
            val timestamp = if (sbn.postTime > 0) sbn.postTime else now

            val added = addNotification(
                packageName = packageName,
                title = title,
                content = text,
                timestamp = timestamp,
                category = sbn.notification.category,
                isOngoing = isOngoing,
                now = now
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
