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
 * Captured notifications are placed in a static synchronized bounded queue capped at 100 items.
 * The queue enforces 15-minute TTL expiration and pre-enqueue PII redaction before items enter memory.
 * Drained by [MainActivity] when Flutter requests them via MethodChannel.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum capacity of the bounded queue. */
        const val MAX_CAPACITY = 100

        /** Maximum allowed queue size to prevent unbounded memory growth (alias for MAX_CAPACITY). */
        const val MAX_QUEUE_SIZE = MAX_CAPACITY

        /** Maximum time-to-live limit for queued items in milliseconds (15 minutes). */
        const val MAX_TTL_MS = 15 * 60 * 1000L // 900,000 ms

        /** Maximum age for queued notifications in milliseconds (alias for MAX_TTL_MS). */
        const val MAX_AGE_MS = MAX_TTL_MS

        /**
         * Thread-safe bounded queue of captured notifications.
         * Access MUST be synchronized on `queue`.
         */
        private val queue = ArrayDeque<NotificationData>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /**
         * Helper methods to log debug messages safely during host JVM unit tests
         * where [Log] methods are not mocked by default.
         */
        private fun logD(tag: String, message: String) {
            try {
                Log.d(tag, message)
            } catch (_: Throwable) {
                // Ignore unmocked android.util.Log in host JVM tests
            }
        }

        private fun logE(tag: String, message: String, throwable: Throwable? = null) {
            try {
                Log.e(tag, message, throwable)
            } catch (_: Throwable) {
                // Ignore unmocked android.util.Log in host JVM tests
            }
        }

        private fun logI(tag: String, message: String) {
            try {
                Log.i(tag, message)
            } catch (_: Throwable) {
                // Ignore unmocked android.util.Log in host JVM tests
            }
        }

        private fun logW(tag: String, message: String) {
            try {
                Log.w(tag, message)
            } catch (_: Throwable) {
                // Ignore unmocked android.util.Log in host JVM tests
            }
        }

        /**
         * Purges expired notifications from the queue based on 15-minute TTL.
         * An item is expired if (currentTimeMillis - item.timestamp) > MAX_TTL_MS.
         */
        @Synchronized
        fun purgeExpired(currentTimeMillis: Long = System.currentTimeMillis()) {
            synchronized(queue) {
                queue.removeAll { item ->
                    (currentTimeMillis - item.timestamp) > MAX_TTL_MS
                }
            }
        }

        /**
         * Removes entries older than [MAX_AGE_MS] from the queue (alias for [purgeExpired]).
         */
        @Synchronized
        fun pruneExpired(now: Long = System.currentTimeMillis()) {
            purgeExpired(now)
        }

        /**
         * Enqueues a [NotificationData] item into the synchronized bounded queue.
         * Redacts PII in title and content, purges expired items, enforces deduplication,
         * and caps queue size at [MAX_CAPACITY] by dropping the oldest item when full.
         */
        @Synchronized
        fun enqueue(data: NotificationData, currentTimeMillis: Long = System.currentTimeMillis()) {
            synchronized(queue) {
                // Purge expired items first
                purgeExpired(currentTimeMillis)

                // Sanitize title and content before enqueueing
                val redactedTitle = NotificationRedactor.redactTitle(data.title)
                val redactedContent = NotificationRedactor.redactContent(data.content)
                val sanitizedData = if (redactedTitle == data.title && redactedContent == data.content) {
                    data
                } else {
                    data.copy(title = redactedTitle, content = redactedContent)
                }

                // Check if item is already expired upon insertion
                if ((currentTimeMillis - sanitizedData.timestamp) > MAX_TTL_MS) {
                    return
                }

                // Ignore if same package, title, and content already exist in remaining queue
                val isDuplicate = queue.any {
                    it.packageName == sanitizedData.packageName &&
                    it.title == sanitizedData.title &&
                    it.content == sanitizedData.content
                }
                if (isDuplicate) {
                    return
                }

                // Drop oldest items if queue reached maximum capacity
                while (queue.size >= MAX_CAPACITY) {
                    queue.poll()
                }

                queue.add(sanitizedData)
            }
        }

        /**
         * Adds a [NotificationData] item to the queue (alias for [enqueue]).
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
        fun drainQueue(currentTimeMillis: Long = System.currentTimeMillis()): List<NotificationData> {
            synchronized(queue) {
                purgeExpired(currentTimeMillis)
                val result = ArrayList<NotificationData>(queue.size)
                while (!queue.isEmpty()) {
                    val item = queue.poll()
                    if (item != null && (currentTimeMillis - item.timestamp) <= MAX_TTL_MS) {
                        result.add(item)
                    }
                }
                return result
            }
        }

        /**
         * Returns the current queue size after purging expired items.
         */
        @Synchronized
        fun queueSize(currentTimeMillis: Long = System.currentTimeMillis()): Int {
            synchronized(queue) {
                purgeExpired(currentTimeMillis)
                return queue.size
            }
        }

        /**
         * Clears all items from the queue and resets the counter.
         */
        @Synchronized
        fun clearQueue() {
            synchronized(queue) {
                queue.clear()
                idCounter = 0L
            }
        }
    }

    private fun addSbnToQueue(sbn: StatusBarNotification, now: Long = System.currentTimeMillis()) {
        try {
            val extras = sbn.notification?.extras
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
                category = sbn.notification?.category,
                isOngoing = isOngoing
            )

            enqueue(data, now)
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
        val removedTitle = sbn.notification?.extras?.getCharSequence("android.title")?.toString()
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
}
