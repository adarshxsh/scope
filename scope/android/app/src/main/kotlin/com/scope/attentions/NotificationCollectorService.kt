package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are placed in a staging buffer which is peeked and acknowledged
 * by [MainActivity] when Flutter requests them via MethodChannel (two-phase handshake).
 *
 * Design decisions:
 *   - Uses a thread-safe synchronized LinkedHashMap preserving insertion order.
 *   - Caps maximum queue size at [MAX_QUEUE_SIZE] (100) and evicts oldest entries (FIFO).
 *   - Enforces 15-minute time-to-live ([MAX_AGE_MS]) to prune stale notifications.
 *   - Supports two-phase non-destructive peeking ([peekQueue]) and explicit acknowledgment ([acknowledgeNotifications]).
 *   - No heavy processing here — just capture and queue.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum allowed queue size to prevent unbounded memory growth. */
        const val MAX_QUEUE_SIZE = 100

        /** Alias for [MAX_QUEUE_SIZE] for backward compatibility. */
        const val MAX_BUFFER_CAPACITY = MAX_QUEUE_SIZE

        /** Maximum time-to-live for queued notifications (15 minutes in milliseconds). */
        const val MAX_AGE_MS = 15 * 60 * 1000L

        private val lock = Any()

        /** Thread-safe unacknowledged staging buffer preserving insertion order. */
        private val buffer = LinkedHashMap<String, NotificationData>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /**
         * Removes entries older than [MAX_AGE_MS] relative to [now] from the buffer.
         */
        @JvmOverloads
        fun pruneExpired(now: Long = System.currentTimeMillis()) {
            synchronized(lock) {
                val iterator = buffer.values.iterator()
                while (iterator.hasNext()) {
                    val item = iterator.next()
                    if (now - item.timestamp > MAX_AGE_MS) {
                        iterator.remove()
                    }
                }
            }
        }

        /**
         * Adds a [NotificationData] item to the buffer after pruning expired items
         * and enforcing maximum queue capacity.
         */
        @JvmOverloads
        fun addNotification(data: NotificationData, now: Long = System.currentTimeMillis()) {
            synchronized(lock) {
                pruneExpired(now)

                // Do not add item if it is already expired relative to current time
                if (now - data.timestamp > MAX_AGE_MS) {
                    return
                }

                // Ignore if same package, title, and content already exist in queue
                val isDuplicate = buffer.values.any {
                    it.packageName == data.packageName && it.title == data.title && it.content == data.content
                }
                if (isDuplicate) {
                    return
                }

                // Evict oldest notification if queue reaches MAX_QUEUE_SIZE before adding new items
                while (buffer.size >= MAX_QUEUE_SIZE) {
                    val oldestKey = buffer.keys.firstOrNull() ?: break
                    buffer.remove(oldestKey)
                }

                buffer[data.id] = data
            }
        }

        /**
         * Peeks and returns all non-expired pending notifications without removing them from memory.
         * Called by [MainActivity] when Flutter requests notifications (Phase 1 of two-phase handshake).
         */
        @JvmOverloads
        fun peekQueue(now: Long = System.currentTimeMillis()): List<NotificationData> {
            synchronized(lock) {
                pruneExpired(now)
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
         * Clears the queue/buffer and resets internal state (for testing or reset).
         */
        fun clearQueue() {
            synchronized(lock) {
                buffer.clear()
                idCounter = 0L
            }
        }

        /**
         * Clears all notifications from the buffer (alias for [clearQueue]).
         */
        fun clearBuffer() = clearQueue()

        /**
         * Helper for unit tests to insert test notifications into the staging buffer.
         */
        fun addNotificationForTest(data: NotificationData) {
            addNotification(data, data.timestamp)
        }

        /**
         * Drains all non-expired notifications from the buffer and returns them.
         * Maintained for backward compatibility.
         */
        @JvmOverloads
        fun drainQueue(now: Long = System.currentTimeMillis()): List<NotificationData> {
            synchronized(lock) {
                pruneExpired(now)
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

    private fun addSbnToQueue(sbn: StatusBarNotification, now: Long = System.currentTimeMillis()) {
        try {
            val extras = sbn.notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: "unknown"
            val timestamp = if (sbn.postTime > 0) sbn.postTime else now

            val data = NotificationData(
                id = "notif_${++idCounter}",
                packageName = packageName,
                title = title,
                content = text,
                timestamp = timestamp,
                category = sbn.notification.category,
                isOngoing = isOngoing
            )

            addNotification(data, now)
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
