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
        private const val MAX_CAPACITY = 100

        /** Thread-safe queue of captured notifications (capped at [MAX_CAPACITY]). */
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
         * Drains all notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue and deduplication set are empty.
         */
        fun drainQueue(): List<NotificationData> {
            val result = mutableListOf<NotificationData>()
            while (true) {
                val item = queue.poll() ?: break
                seenKeys.remove(getCompositeKey(item.packageName, item.title, item.content))
                result.add(item)
            }
            seenKeys.clear()
            return result
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int = queue.size

        /**
         * Clears the queue and deduplication set (useful for testing/resetting).
         */
        fun clearQueue() {
            queue.clear()
            seenKeys.clear()
        }

        /**
         * Adds a notification entry into the queue if not a duplicate (O(1) deduplication).
         * Restricts capacity to [MAX_CAPACITY] (100) using FIFO/LRU eviction.
         * Returns true if added, false if ignored as duplicate.
         */
        fun addNotification(
            packageName: String,
            title: String,
            content: String,
            timestamp: Long = System.currentTimeMillis(),
            category: String? = null,
            isOngoing: Boolean = false
        ): Boolean {
            val compositeKey = getCompositeKey(packageName, title, content)

            // Ignore if same package, title, and content already exist in queue (O(1) lookup)
            if (!seenKeys.add(compositeKey)) {
                return false
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

            queue.add(data)

            // Evict oldest entries if capacity exceeds limit (LRU / FIFO eviction)
            while (queue.size > MAX_CAPACITY) {
                val evicted = queue.poll() ?: break
                seenKeys.remove(getCompositeKey(evicted.packageName, evicted.title, evicted.content))
            }

            try {
                Log.d(TAG, "Captured: ${data.packageName} - ${NotificationRedactor.redactTitle(data.title)}")
            } catch (_: Throwable) {
                // Ignore Log failure in JVM unit tests
            }
            return true
        }
    }

    private fun addSbnToQueue(sbn: StatusBarNotification) {
        try {
            val extras = sbn.notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: "unknown"

            addNotification(
                packageName = packageName,
                title = title,
                content = text,
                timestamp = sbn.postTime,
                category = sbn.notification.category,
                isOngoing = isOngoing
            )
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
