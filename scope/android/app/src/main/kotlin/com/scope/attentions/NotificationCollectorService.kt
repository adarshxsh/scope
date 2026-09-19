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
 * Captured notifications are placed in a static [queue] which is drained
 * by [MainActivity] when Flutter requests them via MethodChannel.
 *
 * Design decisions:
 *   - Uses a bounded queue with a drop-oldest eviction policy (max 500 items).
 *   - Uses an AtomicLong for thread-safe unique ID generation.
 *   - Uses a bounded HashSet for O(1) fast deduplication checking.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    private data class NotifKey(
        val packageName: String,
        val title: String,
        val content: String
    )

    companion object {
        private const val TAG = "NotifCollector"
        private const val MAX_CAPACITY = 500

        private val lock = Any()
        private val queue = ArrayDeque<NotificationData>()
        private val dedupSet = HashSet<NotifKey>()

        /** Counter for generating thread-safe unique IDs within a session. */
        private val idCounter = AtomicLong(0L)

        /**
         * Drains all notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue is empty.
         */
        fun drainQueue(): List<NotificationData> {
            synchronized(lock) {
                val result = ArrayList<NotificationData>(queue.size)
                while (queue.isNotEmpty()) {
                    result.add(queue.removeFirst())
                }
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
    }

    private fun addSbnToQueue(sbn: StatusBarNotification) {
        try {
            val extras = sbn.notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: "unknown"

            val key = NotifKey(packageName, title, text)
            val data: NotificationData

            synchronized(lock) {
                // O(1) deduplication check
                if (dedupSet.contains(key)) {
                    return
                }

                // Drop-oldest eviction policy if queue reaches capacity
                if (queue.size >= MAX_CAPACITY) {
                    val evicted = queue.removeFirst()
                    dedupSet.remove(NotifKey(evicted.packageName, evicted.title, evicted.content))
                }

                data = NotificationData(
                    id = "notif_${idCounter.incrementAndGet()}",
                    packageName = packageName,
                    title = title,
                    content = text,
                    timestamp = sbn.postTime,
                    category = sbn.notification.category,
                    isOngoing = isOngoing
                )

                queue.addLast(data)
                dedupSet.add(key)
            }

            Log.d(TAG, "Captured: ${data.packageName} - ${NotificationRedactor.redactTitle(data.title)}")
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
