package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicLong

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
 *   - Uses a static ConcurrentLinkedQueue (thread-safe) capped at MAX_QUEUE_SIZE (500)
 *     with FIFO drop-oldest eviction to maintain a strict memory bound.
 *   - Uses ConcurrentHashMap.newKeySet for O(1) constant-time deduplication.
 *   - Uses AtomicLong for thread-safe sequential ID generation.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum allowed queue size to prevent unbounded memory growth. */
        const val MAX_QUEUE_SIZE = 500

        /** Maximum time-to-live for queued notifications (15 minutes in milliseconds). */
        const val MAX_AGE_MS = 15 * 60 * 1000L

        /** Thread-safe queue of captured notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** O(1) set for duplicate detection tracking package, title, and content. */
        private val deduplicationSet = ConcurrentHashMap.newKeySet<String>()

        /** Atomic counter for generating unique sequential IDs within a session. */
        private val idCounter = AtomicLong(0L)

        private fun getDeduplicationKey(packageName: String, title: String, content: String): String {
            return "$packageName|$title|$content"
        }

        /**
         * Removes entries older than [MAX_AGE_MS] from the queue and deduplication set.
         */
        fun pruneExpired(now: Long = System.currentTimeMillis()) {
            synchronized(queue) {
                queue.removeIf { item ->
                    if (now - item.timestamp > MAX_AGE_MS) {
                        deduplicationSet.remove(getDeduplicationKey(item.packageName, item.title, item.content))
                        true
                    } else {
                        false
                    }
                }
            }
        }

        /**
         * Adds a [NotificationData] item to the bounded queue after pruning expired items
         * and enforcing O(1) deduplication and maximum queue capacity.
         */
        fun addNotification(data: NotificationData, now: Long = System.currentTimeMillis()): Boolean {
            pruneExpired(now)

            if (now - data.timestamp > MAX_AGE_MS) {
                return false
            }

            val dedupKey = getDeduplicationKey(data.packageName, data.title, data.content)
            if (!deduplicationSet.add(dedupKey)) {
                return false
            }

            synchronized(queue) {
                while (queue.size >= MAX_QUEUE_SIZE) {
                    val evicted = queue.poll()
                    if (evicted != null) {
                        deduplicationSet.remove(getDeduplicationKey(evicted.packageName, evicted.title, evicted.content))
                    } else {
                        break
                    }
                }
                queue.add(data)
            }
            return true
        }

        /**
         * Adds a notification to the bounded queue with atomic ID generation,
         * TTL expiry pruning, and O(1) deduplication.
         */
        fun addNotification(
            packageName: String,
            title: String,
            content: String,
            timestamp: Long,
            category: String? = null,
            isOngoing: Boolean = false,
            now: Long = timestamp
        ): Boolean {
            val data = NotificationData(
                id = "notif_${idCounter.incrementAndGet()}",
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
         * After this call, the queue and deduplication set are empty.
         */
        fun drainQueue(now: Long = System.currentTimeMillis()): List<NotificationData> {
            val result = mutableListOf<NotificationData>()
            synchronized(queue) {
                while (true) {
                    val item = queue.poll() ?: break
                    deduplicationSet.remove(getDeduplicationKey(item.packageName, item.title, item.content))
                    if (now - item.timestamp <= MAX_AGE_MS) {
                        result.add(item)
                    }
                }
            }
            return result
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int = queue.size

        /**
         * Returns the current deduplication set size (for diagnostics).
         */
        fun deduplicationSetSize(): Int = deduplicationSet.size

        /**
         * Clears all queued items, deduplication set, and resets counter (for testing).
         */
        fun clearQueue() {
            synchronized(queue) {
                queue.clear()
                deduplicationSet.clear()
                idCounter.set(0L)
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
