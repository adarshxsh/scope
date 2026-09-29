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
 * Captured notifications are placed in a static bounded queue which is drained
 * by [MainActivity] when Flutter requests them via MethodChannel.
 *
 * Design decisions:
 *   - Uses a synchronized bounded buffer (capacity limit 100 entries, TTL limit 15 minutes)
 *     to prevent unbounded heap growth and evict stale notification payloads automatically.
 *   - Service runs in a separate context from MainActivity.
 *   - No heavy processing here — just capture and queue.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum capacity limit for the notification queue. */
        const val MAX_CAPACITY = 100

        /** Time-to-live limit in milliseconds (15 minutes). */
        const val TTL_MILLIS = 15 * 60 * 1000L

        private val lock = Any()

        /** Thread-safe bounded queue of captured notifications. */
        private val queue = ArrayDeque<NotificationData>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /**
         * Evicts expired notifications older than [TTL_MILLIS].
         */
        fun evictExpired(now: Long = System.currentTimeMillis()) {
            synchronized(lock) {
                val iterator = queue.iterator()
                while (iterator.hasNext()) {
                    val item = iterator.next()
                    if (now - item.timestamp > TTL_MILLIS) {
                        iterator.remove()
                    }
                }
            }
        }

        /**
         * Adds a notification item to the bounded queue.
         * Runs eviction first, ignores duplicates, and evicts the head item if capacity is reached.
         * Returns true if added, false if ignored.
         */
        fun addNotification(data: NotificationData, now: Long = System.currentTimeMillis()): Boolean {
            synchronized(lock) {
                evictExpired(now)

                val isDuplicate = queue.any {
                    it.packageName == data.packageName && it.title == data.title && it.content == data.content
                }
                if (isDuplicate) {
                    return false
                }

                if (queue.size >= MAX_CAPACITY) {
                    queue.removeFirst()
                }

                queue.addLast(data)
                return true
            }
        }

        /**
         * Drains all valid notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue is empty.
         */
        fun drainQueue(now: Long = System.currentTimeMillis()): List<NotificationData> {
            synchronized(lock) {
                evictExpired(now)
                val result = queue.toList()
                queue.clear()
                return result
            }
        }

        /**
         * Returns the current queue size after evicting expired notifications.
         */
        fun queueSize(now: Long = System.currentTimeMillis()): Int {
            synchronized(lock) {
                evictExpired(now)
                return queue.size
            }
        }

        /**
         * Clears the queue and resets state (primarily for testing).
         */
        fun clearQueue() {
            synchronized(lock) {
                queue.clear()
                idCounter = 0L
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

            val nextId = synchronized(lock) { ++idCounter }
            val data = NotificationData(
                id = "notif_$nextId",
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
