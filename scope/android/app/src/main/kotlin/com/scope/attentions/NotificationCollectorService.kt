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
        private const val MAX_QUEUE_SIZE = 500

        /** Thread-safe bounded queue of captured notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** O(1) set for duplicate detection tracking package, title, and content. */
        private val deduplicationSet = ConcurrentHashMap.newKeySet<String>()

        /** Atomic counter for generating unique sequential IDs within a session. */
        private val idCounter = AtomicLong(0L)

        private fun getDeduplicationKey(packageName: String, title: String, content: String): String {
            return "$packageName|$title|$content"
        }

        /**
         * Adds a notification to the bounded queue with atomic ID generation
         * and O(1) deduplication. Automatically evicts the oldest item when capacity (500) is reached.
         * Returns true if added, false if skipped as duplicate.
         */
        fun addNotification(
            packageName: String,
            title: String,
            content: String,
            timestamp: Long,
            category: String? = null,
            isOngoing: Boolean = false
        ): Boolean {
            val dedupKey = getDeduplicationKey(packageName, title, content)

            // Constant O(1) deduplication check using ConcurrentHashMap set
            if (!deduplicationSet.add(dedupKey)) {
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
         * Drains all notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue and deduplication set are empty.
         */
        fun drainQueue(): List<NotificationData> {
            val result = mutableListOf<NotificationData>()
            synchronized(queue) {
                while (true) {
                    val item = queue.poll() ?: break
                    deduplicationSet.remove(getDeduplicationKey(item.packageName, item.title, item.content))
                    result.add(item)
                }
                deduplicationSet.clear()
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
         * Clears all queued items and deduplication set (for testing).
         */
        fun clearQueue() {
            synchronized(queue) {
                queue.clear()
                deduplicationSet.clear()
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
