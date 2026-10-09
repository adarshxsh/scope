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
 * Captured notifications are placed in a static fixed-capacity ring buffer
 * ([ringBuffer]) which automatically evicts the oldest un-drained notification
 * when maximum capacity (500) is reached. The buffer is drained by [MainActivity]
 * when Flutter requests them via MethodChannel.
 *
 * Design decisions:
 *   - Uses a fixed-capacity [NotificationRingBuffer] (capacity = 500) with O(1)
 *     insertions and evictions to bound memory footprint and prevent OOMs.
 *   - No heavy processing here — just capture and queue.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"
        const val DEFAULT_CAPACITY = 500
        const val MAX_QUEUE_SIZE = DEFAULT_CAPACITY

        /** Maximum time-to-live for queued notifications (15 minutes in milliseconds). */
        const val MAX_AGE_MS = 15 * 60 * 1000L

        /** Thread-safe ring buffer of captured notifications. */
        private val ringBuffer = NotificationRingBuffer(DEFAULT_CAPACITY)

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /**
         * Removes entries older than [MAX_AGE_MS] from the ring buffer.
         */
        fun pruneExpired(now: Long = System.currentTimeMillis()) {
            ringBuffer.removeIf { now - it.timestamp > MAX_AGE_MS }
        }

        /**
         * Adds a [NotificationData] item to the ring buffer after pruning expired items
         * and checking for duplicate entries.
         */
        fun addNotification(data: NotificationData, now: Long = System.currentTimeMillis()) {
            pruneExpired(now)

            // Do not add item if it is already expired relative to current time
            if (now - data.timestamp > MAX_AGE_MS) {
                return
            }

            // Ignore if same package, title, and content already exist in queue
            val isDuplicate = ringBuffer.any {
                it.packageName == data.packageName && it.title == data.title && it.content == data.content
            }
            if (isDuplicate) {
                return
            }

            ringBuffer.add(data)
        }

        /**
         * Drains all non-expired notifications from the ring buffer and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the ring buffer is empty.
         */
        fun drainQueue(now: Long = System.currentTimeMillis()): List<NotificationData> {
            pruneExpired(now)
            return ringBuffer.drain()
        }

        /**
         * Clears the queue and resets internal state (for testing).
         */
        fun clearQueue() {
            ringBuffer.clear()
            idCounter = 0L
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int = ringBuffer.size

        /**
         * Returns the total count of evicted notifications due to buffer overflow.
         */
        fun droppedCount(): Long = ringBuffer.droppedCount

        /**
         * Resets queue state and counters (for testing and diagnostics).
         */
        fun reset() {
            ringBuffer.clear()
            idCounter = 0L
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
            logD(TAG, "Captured: ${data.packageName} - ${NotificationRedactor.redactTitle(data.title)}")
        } catch (e: Exception) {
            logE(TAG, "Error capturing/adding notification", e)
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
        logD(TAG, "Removed: ${sbn.packageName} - ${NotificationRedactor.redactTitle(removedTitle)}")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        logI(TAG, "NotificationCollectorService connected")
        try {
            val activeNotifs = activeNotifications
            if (activeNotifs != null) {
                logD(TAG, "Syncing ${activeNotifs.size} existing notifications from panel")
                for (sbn in activeNotifs) {
                    addSbnToQueue(sbn)
                }
            }
        } catch (e: Exception) {
            logE(TAG, "Error fetching active notifications on connect", e)
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        logW(TAG, "NotificationCollectorService disconnected")
    }

    private fun logD(tag: String, msg: String) {
        try { Log.d(tag, msg) } catch (_: Throwable) {}
    }

    private fun logI(tag: String, msg: String) {
        try { Log.i(tag, msg) } catch (_: Throwable) {}
    }

    private fun logW(tag: String, msg: String) {
        try { Log.w(tag, msg) } catch (_: Throwable) {}
    }

    private fun logE(tag: String, msg: String, e: Throwable? = null) {
        try { Log.e(tag, msg, e) } catch (_: Throwable) {}
    }
}
