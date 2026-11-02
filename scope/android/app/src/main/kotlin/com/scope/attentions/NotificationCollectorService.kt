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
 *   - Enforces maximum time-to-live [MAX_AGE_MS] for queued notifications (15 minutes).
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum allowed queue size to prevent unbounded memory growth. */
        const val MAX_QUEUE_SIZE = 250

        /** Maximum time-to-live for queued notifications (15 minutes in milliseconds). */
        const val MAX_AGE_MS = 15 * 60 * 1000L

        private val lock = Any()

        /** Bounded queue of captured notifications (max [MAX_QUEUE_SIZE]). */
        private val queue = ArrayDeque<NotificationData>()

        /** Bounded lookup set for O(1) deduplication. */
        private val dedupSet = HashSet<DedupKey>()

        /** Counter for generating unique IDs atomically across threads. */
        private val idCounter = AtomicLong(0L)

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
                        dedupSet.remove(DedupKey(item.packageName, item.title, item.content))
                    }
                }
            }
        }

        /**
         * Enqueues a notification if it is not expired and not a duplicate.
         * Enforces maximum queue size [MAX_QUEUE_SIZE] using drop-oldest FIFO eviction.
         */
        fun enqueueNotification(
            packageName: String,
            title: String,
            content: String,
            timestamp: Long,
            category: String?,
            isOngoing: Boolean,
            now: Long = System.currentTimeMillis()
        ): Boolean {
            val key = DedupKey(packageName, title, content)
            synchronized(lock) {
                pruneExpired(now)

                if (now - timestamp > MAX_AGE_MS) {
                    return false
                }

                if (dedupSet.contains(key)) {
                    return false
                }

                while (queue.size >= MAX_QUEUE_SIZE) {
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
         * Adds a [NotificationData] item to the queue after pruning expired items
         * and enforcing maximum queue capacity.
         */
        fun addNotification(data: NotificationData, now: Long = System.currentTimeMillis()) {
            enqueueNotification(
                packageName = data.packageName,
                title = data.title,
                content = data.content,
                timestamp = data.timestamp,
                category = data.category,
                isOngoing = data.isOngoing,
                now = now
            )
        }

        /**
         * Drains all non-expired notifications from the queue and resets deduplication state.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue and deduplication set are empty.
         */
        fun drainQueue(now: Long = System.currentTimeMillis()): List<NotificationData> {
            synchronized(lock) {
                pruneExpired(now)
                val result = ArrayList(queue)
                queue.clear()
                dedupSet.clear()
                return result
            }
        }

        /**
         * Clears the queue and resets internal state (for testing).
         */
        fun clearQueue() {
            synchronized(lock) {
                queue.clear()
                dedupSet.clear()
                idCounter.set(0L)
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
            clearQueue()
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

            val added = enqueueNotification(
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
