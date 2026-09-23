package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.ArrayDeque

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are placed in a static bounded FIFO buffer [queue]
 * with an index [dedupSet] for O(1) deduplication, which is drained by
 * [MainActivity] when Flutter requests them via MethodChannel.
 *
 * Design decisions:
 *   - Bounded FIFO buffer with max capacity of 200 items to prevent heap memory exhaustion.
 *   - Drops oldest notification when capacity is reached.
 *   - Synchronized monitor lock prevents race conditions between background ingestion
 *     and foreground draining.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    private data class NotificationKey(
        val packageName: String,
        val title: String,
        val content: String
    )

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum capacity for the in-memory notification queue. */
        const val MAX_CAPACITY = 200

        private val lock = Any()

        /** Bounded FIFO queue of captured notifications. */
        private val queue = ArrayDeque<NotificationData>()

        /** Hash set index for O(1) deduplication lookups. */
        private val dedupSet = HashSet<NotificationKey>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /**
         * Adds a [NotificationData] to the queue if it's not a duplicate.
         * Enforces the hard limit of [MAX_CAPACITY] items by evicting the oldest item.
         * Resets/updates both the queue and deduplication set atomically.
         * Returns true if added, false if ignored as duplicate.
         */
        fun addNotification(data: NotificationData): Boolean = synchronized(lock) {
            val key = NotificationKey(data.packageName, data.title, data.content)
            if (dedupSet.contains(key)) {
                return false
            }

            if (queue.size >= MAX_CAPACITY) {
                val oldest = queue.removeFirst()
                dedupSet.remove(NotificationKey(oldest.packageName, oldest.title, oldest.content))
            }

            queue.addLast(data)
            dedupSet.add(key)
            return true
        }

        /**
         * Drains all notifications from the queue and returns them in FIFO order.
         * Called by [MainActivity] when Flutter requests notifications.
         * Resets both the queue and deduplication index atomically.
         */
        fun drainQueue(): List<NotificationData> = synchronized(lock) {
            val result = ArrayList(queue)
            queue.clear()
            dedupSet.clear()
            return result
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int = synchronized(lock) {
            return queue.size
        }

        /**
         * Clears the queue and deduplication set (primarily for testing/reset).
         */
        fun clearQueue() = synchronized(lock) {
            queue.clear()
            dedupSet.clear()
        }
    }

    private fun addSbnToQueue(sbn: StatusBarNotification) {
        try {
            val extras = sbn.notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: "unknown"

            val data = NotificationData(
                id = "notif_${++idCounter}",
                packageName = packageName,
                title = title,
                content = text,
                timestamp = sbn.postTime,
                category = sbn.notification.category,
                isOngoing = isOngoing
            )

            val added = addNotification(data)
            if (added) {
                Log.d(TAG, "Captured: ${data.packageName} - ${NotificationRedactor.redactTitle(data.title)}")
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
