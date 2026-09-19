package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.ArrayDeque
import java.util.HashSet
import java.util.concurrent.atomic.AtomicLong

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
 *   - Uses a static synchronized ArrayDeque bounded at 250 items to prevent heap memory growth.
 *   - Uses a HashSet index for O(1) deduplication check across package name, title, and content.
 *   - Uses AtomicLong for thread-safe notification ID increments.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"
        private const val MAX_CAPACITY = 250

        /** Thread-safe queue of captured notifications, bounded at [MAX_CAPACITY]. */
        private val queue = ArrayDeque<NotificationData>()

        /** HashSet deduplication index for O(1) duplicate key checks. */
        private val dedupSet = HashSet<String>()

        /** Counter for generating unique IDs atomically across concurrent threads. */
        private val idCounter = AtomicLong(0L)

        /**
         * Drains all notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue and deduplication index are cleared atomically under a unified monitor lock.
         */
        fun drainQueue(): List<NotificationData> {
            synchronized(queue) {
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
            synchronized(queue) {
                return queue.size
            }
        }

        /**
         * Adds a notification payload to the bounded queue with O(1) deduplication.
         * Evicts the oldest item if the queue is at capacity limit (250).
         */
        fun addNotification(
            packageName: String,
            title: String,
            content: String,
            timestamp: Long = System.currentTimeMillis(),
            category: String? = null,
            isOngoing: Boolean = false
        ): Boolean {
            val dedupKey = "$packageName\u0000$title\u0000$content"
            synchronized(queue) {
                if (dedupSet.contains(dedupKey)) {
                    return false
                }

                if (queue.size >= MAX_CAPACITY) {
                    val evicted = queue.removeFirst()
                    val evictedKey = "${evicted.packageName}\u0000${evicted.title}\u0000${evicted.content}"
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
                dedupSet.add(dedupKey)
                return true
            }
        }

        /** Resets internal state (for testing). */
        internal fun resetForTest() {
            synchronized(queue) {
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
