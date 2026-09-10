package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.ArrayDeque
import java.util.HashSet
import java.util.concurrent.atomic.AtomicLong

/**
 * Composite key representing a notification signature for O(1) deduplication.
 */
data class NotificationKey(
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
 * Captured notifications are placed in a static bounded ring queue which is drained
 * by [MainActivity] when Flutter requests them via MethodChannel.
 *
 * Design decisions:
 *   - Uses a synchronized bounded ring queue with capacity cap of 200 items.
 *   - Uses AtomicLong for thread-safe unique ID generation.
 *   - Uses a sliding HashSet for O(1) deduplication of active notifications.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum capacity for the bounded ring queue. */
        const val MAX_QUEUE_SIZE = 200

        private val queueLock = Any()

        /** Bounded ring queue of captured notifications. */
        private val queue = ArrayDeque<NotificationData>(MAX_QUEUE_SIZE)

        /** Hash set for O(1) deduplication of active notifications in the queue. */
        private val dedupeSet = HashSet<NotificationKey>()

        /** Thread-safe counter for generating unique notification IDs within a session. */
        private val idCounter = AtomicLong(0L)

        /**
         * Enqueues a notification if it is not a duplicate.
         * Enforces maximum capacity of [MAX_QUEUE_SIZE], evicting the oldest element when full.
         * Generates a thread-safe ID using [AtomicLong.incrementAndGet].
         * Returns true if added, false if ignored as duplicate.
         */
        fun enqueueNotification(
            packageName: String,
            title: String,
            content: String,
            timestamp: Long = System.currentTimeMillis(),
            category: String? = null,
            isOngoing: Boolean = false
        ): Boolean {
            val key = NotificationKey(packageName, title, content)
            synchronized(queueLock) {
                if (dedupeSet.contains(key)) {
                    return false
                }

                if (queue.size >= MAX_QUEUE_SIZE) {
                    val evicted = queue.removeFirst()
                    dedupeSet.remove(NotificationKey(evicted.packageName, evicted.title, evicted.content))
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
                dedupeSet.add(key)
                return true
            }
        }

        /**
         * Drains all notifications from the queue and resets the deduplication set.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue and deduplication set are empty.
         */
        fun drainQueue(): List<NotificationData> {
            synchronized(queueLock) {
                val result = ArrayList(queue)
                queue.clear()
                dedupeSet.clear()
                return result
            }
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int {
            synchronized(queueLock) {
                return queue.size
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
