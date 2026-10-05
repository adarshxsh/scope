package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.concurrent.ConcurrentLinkedQueue

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
 *   - Uses a static ConcurrentLinkedQueue (thread-safe, lock-free) because
 *     the service runs in a separate context from MainActivity.
 *   - No heavy processing here — just capture and queue.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum capacity for the unacknowledged staging buffer to bound memory usage. */
        private const val MAX_BUFFER_CAPACITY = 1000

        private val lock = Any()

        /** Thread-safe unacknowledged staging buffer preserving insertion order. */
        private val buffer = LinkedHashMap<String, NotificationData>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /**
         * Peeks and returns all pending notifications without removing them from memory.
         * Called by [MainActivity] when Flutter requests notifications (Phase 1 of two-phase handshake).
         */
        fun peekQueue(): List<NotificationData> {
            synchronized(lock) {
                return buffer.values.toList()
            }
        }

        /**
         * Alias for [peekQueue] for clarity.
         */
        fun getPendingNotifications(): List<NotificationData> = peekQueue()

        /**
         * Explicitly acknowledges notifications by ID, removing them from the native staging buffer.
         * Called by [MainActivity] after Flutter successfully persists notifications (Phase 2 of two-phase handshake).
         * Returns the number of items successfully removed.
         */
        fun acknowledgeNotifications(ids: Collection<String>): Int {
            if (ids.isEmpty()) return 0
            val idSet = ids.toSet()
            var count = 0
            synchronized(lock) {
                val iterator = buffer.entries.iterator()
                while (iterator.hasNext()) {
                    val entry = iterator.next()
                    if (entry.key in idSet) {
                        iterator.remove()
                        count++
                    }
                }
            }
            return count
        }

        /**
         * Clears all notifications from the buffer (for testing or reset).
         */
        fun clearBuffer() {
            synchronized(lock) {
                buffer.clear()
            }
        }

        /**
         * Helper for unit tests to insert test notifications into the staging buffer.
         */
        fun addNotificationForTest(data: NotificationData) {
            synchronized(lock) {
                if (buffer.size >= MAX_BUFFER_CAPACITY) {
                    val oldestKey = buffer.keys.firstOrNull()
                    if (oldestKey != null) {
                        buffer.remove(oldestKey)
                    }
                }
                buffer[data.id] = data
            }
        }

        /**
         * Legacy method: drains all notifications from the buffer and returns them.
         * Maintained for backward compatibility.
         */
        fun drainQueue(): List<NotificationData> {
            synchronized(lock) {
                val result = buffer.values.toList()
                buffer.clear()
                return result
            }
        }

        /**
         * Returns the current queue/buffer size (for diagnostics).
         */
        fun queueSize(): Int {
            synchronized(lock) {
                return buffer.size
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

            synchronized(lock) {
                // Ignore if same package, title, and content already exist in buffer
                val isDuplicate = buffer.values.any {
                    it.packageName == packageName && it.title == title && it.content == text
                }
                if (isDuplicate) {
                    return
                }

                // Bound memory consumption by enforcing maximum capacity limit
                if (buffer.size >= MAX_BUFFER_CAPACITY) {
                    val oldestKey = buffer.keys.firstOrNull()
                    if (oldestKey != null) {
                        buffer.remove(oldestKey)
                    }
                }

                val data = NotificationData(
                    id = "notif_${++idCounter}",
                    packageName = packageName,
                    title = title,
                    content = text,
                    timestamp = sbn.postTime,
                    category = sbn.notification.category,
                    isOngoing = isOngoing
                )

                buffer[data.id] = data
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
