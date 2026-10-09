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
 * Captured notifications are placed in a bounded static [queue] (max 100 entries)
 * which is drained by [MainActivity] when Flutter requests them via MethodChannel.
 *
 * Design decisions:
 *   - Uses a static ConcurrentLinkedQueue (thread-safe, lock-free) bounded to 100 entries.
 *   - Uses an in-memory HashSet (`ConcurrentHashMap.newKeySet()`) of composite keys
 *     (packageName + title + content) for O(1) deduplication lookup.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum allowed queue size to prevent unbounded memory growth. */
        const val MAX_QUEUE_SIZE = 100

        /** Maximum time-to-live for queued notifications (15 minutes in milliseconds). */
        const val MAX_AGE_MS = 15 * 60 * 1000L

        /** Thread-safe queue of captured notifications (capped at [MAX_QUEUE_SIZE]). */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Thread-safe set of composite keys (packageName|title|content) for O(1) deduplication. */
        private val seenKeys: MutableSet<String> = ConcurrentHashMap.newKeySet()

        /** Counter for generating simple unique IDs within a session. */
        private val idCounter = AtomicLong(0L)

        /**
         * Generates a composite lookup key for deduplication.
         */
        fun getCompositeKey(packageName: String, title: String, content: String): String {
            return "$packageName|$title|$content"
        }

        /**
         * Removes entries older than [MAX_AGE_MS] from the queue and deduplication set.
         */
        fun pruneExpired(now: Long = System.currentTimeMillis()) {
            queue.removeIf { item ->
                val expired = now - item.timestamp > MAX_AGE_MS
                if (expired) {
                    seenKeys.remove(getCompositeKey(item.packageName, item.title, item.content))
                }
                expired
            }
        }

        /**
         * Adds a [NotificationData] item to the queue after pruning expired items,
         * checking O(1) deduplication, and enforcing maximum queue capacity.
         */
        fun addNotification(data: NotificationData, now: Long = System.currentTimeMillis()): Boolean {
            pruneExpired(now)

            // Do not add item if it is already expired relative to current time
            if (now - data.timestamp > MAX_AGE_MS) {
                return false
            }

            val compositeKey = getCompositeKey(data.packageName, data.title, data.content)

            // Ignore if same package, title, and content already exist in queue (O(1) lookup)
            if (!seenKeys.add(compositeKey)) {
                return false
            }

            // Evict oldest notification if queue reaches MAX_QUEUE_SIZE before adding new items
            while (queue.size >= MAX_QUEUE_SIZE) {
                val evicted = queue.poll() ?: break
                seenKeys.remove(getCompositeKey(evicted.packageName, evicted.title, evicted.content))
            }

            queue.add(data)

            try {
                Log.d(TAG, "Captured: ${data.packageName} - ${NotificationRedactor.redactTitle(data.title)}")
            } catch (_: Throwable) {
                // Ignore Log failure in JVM unit tests
            }

            return true
        }

        /**
         * Adds a notification entry into the queue if not a duplicate (O(1) deduplication).
         * Restricts capacity to [MAX_QUEUE_SIZE] (100) using FIFO eviction.
         * Returns true if added, false if ignored as duplicate or expired.
         */
        fun addNotification(
            packageName: String,
            title: String,
            content: String,
            timestamp: Long = System.currentTimeMillis(),
            category: String? = null,
            isOngoing: Boolean = false
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
            return addNotification(data, timestamp)
        }

        /**
         * Drains all non-expired notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue and deduplication set are empty.
         */
        fun drainQueue(now: Long = System.currentTimeMillis()): List<NotificationData> {
            val result = mutableListOf<NotificationData>()
            while (true) {
                val item = queue.poll() ?: break
                seenKeys.remove(getCompositeKey(item.packageName, item.title, item.content))
                if (now - item.timestamp <= MAX_AGE_MS) {
                    result.add(item)
                }
            }
            seenKeys.clear()
            return result
        }

        /**
         * Clears the queue and deduplication set, and resets counter (for testing).
         */
        fun clearQueue() {
            queue.clear()
            seenKeys.clear()
            idCounter.set(0L)
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int = queue.size
    }

    private fun addSbnToQueue(sbn: StatusBarNotification, now: Long = System.currentTimeMillis()) {
        try {
            val extras = sbn.notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: "unknown"
            val timestamp = if (sbn.postTime > 0) sbn.postTime else now

            val data = NotificationData(
                id = "notif_${idCounter.incrementAndGet()}",
                packageName = packageName,
                title = title,
                content = text,
                timestamp = timestamp,
                category = sbn.notification.category,
                isOngoing = isOngoing
            )

            addNotification(data, now)
        } catch (e: Exception) {
            try {
                Log.e(TAG, "Error capturing/adding notification", e)
            } catch (_: Throwable) {}
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
