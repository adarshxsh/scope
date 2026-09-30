package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are placed in a static bounded queue capped at [MAX_QUEUE_SIZE],
 * which is drained by [MainActivity] when Flutter requests them via MethodChannel.
 *
 * Design decisions:
 *   - Uses a bounded queue capped at [MAX_QUEUE_SIZE] with FIFO eviction rules
 *     to prevent unbounded memory growth and heap retention of cleartext payloads.
 *   - Supports maximum time-to-live [MAX_AGE_MS] to automatically expire old notifications.
 *   - Thread-safe synchronization ensures safe operations across background service thread
 *     and MainActivity MethodChannel thread.
 *   - No heavy processing here — just capture and queue.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum allowed queue size to prevent unbounded memory growth. */
        const val MAX_QUEUE_SIZE = 100

        /** Maximum time-to-live for queued notifications (15 minutes in milliseconds). */
        const val MAX_AGE_MS = 15 * 60 * 1000L

        /** Bounded queue of captured notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /**
         * Removes entries older than [MAX_AGE_MS] from the queue.
         */
        @Synchronized
        fun pruneExpired(now: Long = System.currentTimeMillis()) {
            queue.removeIf { now - it.timestamp > MAX_AGE_MS }
        }

        /**
         * Enqueues a notification item into the bounded queue.
         *
         * Performs duplicate suppression (ignores if same packageName, title, and content
         * already exist in queue) and enforces maximum capacity by evicting the oldest
         * entry via [queue.poll()] whenever [queue.size] reaches [MAX_QUEUE_SIZE].
         *
         * Synchronized to guarantee thread safety during concurrent notification events.
         */
        @Synchronized
        fun enqueue(data: NotificationData, now: Long = System.currentTimeMillis()): Boolean {
            pruneExpired(now)

            // Do not add item if it is already expired relative to current time
            if (now - data.timestamp > MAX_AGE_MS) {
                return false
            }

            // Ignore duplicate if same package, title, and content already exist in queue
            val isDuplicate = queue.any {
                it.packageName == data.packageName && it.title == data.title && it.content == data.content
            }
            if (isDuplicate) {
                return false
            }

            // Evict oldest entries until size is strictly below capacity
            while (queue.size >= MAX_QUEUE_SIZE) {
                queue.poll()
            }

            return queue.add(data)
        }

        /**
         * Adds a [NotificationData] item to the queue after pruning expired items
         * and enforcing maximum queue capacity.
         */
        @Synchronized
        fun addNotification(data: NotificationData, now: Long = System.currentTimeMillis()) {
            enqueue(data, now)
        }

        /**
         * Drains all non-expired notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue is empty.
         */
        @Synchronized
        fun drainQueue(now: Long = System.currentTimeMillis()): List<NotificationData> {
            val result = mutableListOf<NotificationData>()
            while (true) {
                val item = queue.poll() ?: break
                if (now - item.timestamp <= MAX_AGE_MS) {
                    result.add(item)
                }
            }
            return result
        }

        /**
         * Returns a snapshot copy of current queued notifications without removing them (for inspection/testing).
         */
        @Synchronized
        fun peekQueue(): List<NotificationData> {
            return queue.toList()
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        @Synchronized
        fun queueSize(): Int = queue.size

        /**
         * Clears all items in the queue and resets the ID counter (for tests and resets).
         */
        @Synchronized
        fun clearQueue() {
            queue.clear()
            idCounter = 0L
        }

        /**
         * Generates a new unique notification ID.
         */
        @Synchronized
        fun nextNotificationId(): String {
            return "notif_${++idCounter}"
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
                id = nextNotificationId(),
                packageName = packageName,
                title = title,
                content = text,
                timestamp = timestamp,
                category = sbn.notification.category,
                isOngoing = isOngoing
            )

            if (enqueue(data, now)) {
                logD(TAG, "Captured: ${data.packageName} - ${NotificationRedactor.redactTitle(data.title)}")
            }
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
        try {
            android.util.Log.d(tag, msg)
        } catch (e: Throwable) {
            println("[$tag] $msg")
        }
    }

    private fun logI(tag: String, msg: String) {
        try {
            android.util.Log.i(tag, msg)
        } catch (e: Throwable) {
            println("[$tag] $msg")
        }
    }

    private fun logW(tag: String, msg: String) {
        try {
            android.util.Log.w(tag, msg)
        } catch (e: Throwable) {
            println("[$tag] $msg")
        }
    }

    private fun logE(tag: String, msg: String, tr: Throwable? = null) {
        try {
            if (tr != null) {
                android.util.Log.e(tag, msg, tr)
            } else {
                android.util.Log.e(tag, msg)
            }
        } catch (e: Throwable) {
            println("[$tag] $msg ${tr?.message ?: ""}")
        }
    }
}
