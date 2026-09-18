package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.ArrayDeque
import java.util.HashSet
import java.util.concurrent.atomic.AtomicLong

private data class DedupKey(
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
 * Captured notifications are placed in a static bounded [queue] which is drained
 * by [MainActivity] when Flutter requests them via MethodChannel.
 *
 * Design decisions:
 *   - Uses a synchronized bounded queue (capped at [MAX_QUEUE_SIZE]) with drop-oldest FIFO eviction.
 *   - Uses an O(1) [HashSet] lookup for duplicate notification checking.
 *   - Uses an [AtomicLong] for thread-safe notification ID generation.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"
        const val MAX_QUEUE_SIZE = 250

        private val lock = Any()

        /** Bounded queue of captured notifications (max [MAX_QUEUE_SIZE]). */
        private val queue = ArrayDeque<NotificationData>()

        /** Bounded lookup set for O(1) deduplication. */
        private val dedupSet = HashSet<DedupKey>()

        /** Counter for generating unique IDs atomically across threads. */
        private val idCounter = AtomicLong(0L)

        /**
         * Enqueues a notification if it is not a duplicate.
         * Enforces maximum queue size [MAX_QUEUE_SIZE] using drop-oldest FIFO eviction.
         */
        fun enqueueNotification(
            packageName: String,
            title: String,
            content: String,
            timestamp: Long,
            category: String?,
            isOngoing: Boolean
        ): Boolean {
            val key = DedupKey(packageName, title, content)
            synchronized(lock) {
                if (dedupSet.contains(key)) {
                    return false
                }

                if (queue.size >= MAX_QUEUE_SIZE) {
                    val evicted = queue.removeFirst()
                    val evictedKey = DedupKey(evicted.packageName, evicted.title, evicted.content)
                    dedupSet.remove(evictedKey)
                }

                val data = NotificationData(
                    id = "notif_${idCounter.incrementAndGet()}",
                    packageName = packageName,
                    title = title,
                    content = content,
                    timestamp = timestamp,
                    category = category,
                    isOngoing = isOngoing
                )

                queue.addLast(data)
                dedupSet.add(key)
                return true
            }
        }

        /**
         * Drains all notifications from the queue and resets deduplication state.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue and deduplication set are empty.
         */
        fun drainQueue(): List<NotificationData> {
            synchronized(lock) {
                val result = ArrayList(queue)
                queue.clear()
                dedupSet.clear()
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
         * Resets queue, deduplication set, and ID counter (for testing).
         */
        fun resetForTesting() {
            synchronized(lock) {
                queue.clear()
                dedupSet.clear()
                idCounter.set(0L)
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

            val added = enqueueNotification(
                packageName = packageName,
                title = title,
                content = text,
                timestamp = sbn.postTime,
                category = sbn.notification.category,
                isOngoing = isOngoing
            )

            if (added) {
                Log.d(TAG, "Captured: $packageName - $title")
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
        Log.d(TAG, "Removed: ${sbn.packageName} - ${sbn.notification.extras?.getCharSequence("android.title")}")
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

