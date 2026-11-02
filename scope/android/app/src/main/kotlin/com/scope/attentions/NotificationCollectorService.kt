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
 * Captured notifications are placed in a static bounded queue which is drained
 * by [MainActivity] when Flutter requests them via MethodChannel.
 *
 * Architectural & Security Guardrails:
 *   - Bounded static queue (MAX_QUEUE_SIZE = 100) with drop-oldest eviction policy.
 *   - TTL eviction (MAX_AGE_MS = 15 minutes) for stale queued notifications.
 *   - O(1) deduplication tracking using a HashSet signature map to avoid O(N^2) overhead.
 *   - AtomicLong for thread-safe session ID generation.
 *   - Ingestion filtering excluding ongoing alerts and noise categories (progress, navigation, service, sys, system, transport, status).
 *   - PII log sanitization via [NotificationRedactor] to prevent sensitive logcat exposure.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum allowed queue size to prevent unbounded memory growth. */
        const val MAX_QUEUE_SIZE = 100

        /** Maximum time-to-live for queued notifications (15 minutes in milliseconds). */
        const val MAX_AGE_MS = 15 * 60 * 1000L

        /** Excluded background/system noise categories at ingestion. */
        private val EXCLUDED_CATEGORIES = setOf(
            "progress",
            "navigation",
            "service",
            "sys",
            "system",
            "transport",
            "status"
        )

        private val lock = Any()

        /** Bounded FIFO queue of captured notifications. */
        private val queue = ArrayDeque<NotificationData>()

        /** O(1) lookup set for duplicate detection tracking "packageName:title:content". */
        private val dedupSet = HashSet<String>()

        /** Atomic counter for generating simple unique IDs within a session. */
        private val idCounter = AtomicLong(0L)

        private fun getDedupKey(data: NotificationData): String =
            "${data.packageName}:${data.title}:${data.content}"

        private fun getDedupKey(packageName: String, title: String, content: String): String =
            "$packageName:$title:$content"

        /**
         * Removes entries older than [MAX_AGE_MS] from the queue and updates dedupSet.
         */
        fun pruneExpired(now: Long = System.currentTimeMillis()) {
            synchronized(lock) {
                val iterator = queue.iterator()
                while (iterator.hasNext()) {
                    val item = iterator.next()
                    if (now - item.timestamp > MAX_AGE_MS) {
                        iterator.remove()
                        dedupSet.remove(getDedupKey(item))
                    }
                }
            }
        }

        /**
         * Adds a [NotificationData] item to the queue after pruning expired items
         * and enforcing maximum queue capacity.
         */
        fun addNotification(data: NotificationData, now: Long = System.currentTimeMillis()) {
            synchronized(lock) {
                pruneExpired(now)

                // Do not add item if it is already expired relative to current time
                if (now - data.timestamp > MAX_AGE_MS) {
                    return
                }

                val dedupKey = getDedupKey(data)

                // Ignore if duplicate already exists in queue
                if (dedupSet.contains(dedupKey)) {
                    return
                }

                // Evict oldest notification if queue reaches MAX_QUEUE_SIZE
                while (queue.size >= MAX_QUEUE_SIZE) {
                    val evicted = queue.poll()
                    if (evicted != null) {
                        dedupSet.remove(getDedupKey(evicted))
                    }
                }

                queue.add(data)
                dedupSet.add(dedupKey)
            }
        }

        /**
         * Enqueues a notification with input validation, filtering, O(1) deduplication,
         * and drop-oldest FIFO queue bounding.
         *
         * @return true if enqueued successfully, false if rejected (duplicate/filtered/expired).
         */
        fun enqueueNotification(
            packageName: String,
            title: String,
            content: String,
            timestamp: Long,
            category: String?,
            isOngoing: Boolean,
            now: Long = System.currentTimeMillis()
        ): Boolean {
            // Filter ongoing system alerts
            if (isOngoing) {
                return false
            }

            // Filter background noise categories
            val catLower = category?.lowercase()
            if (catLower != null && EXCLUDED_CATEGORIES.contains(catLower)) {
                return false
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

            synchronized(lock) {
                pruneExpired(now)

                if (now - timestamp > MAX_AGE_MS) {
                    return false
                }

                val dedupKey = getDedupKey(data)
                if (dedupSet.contains(dedupKey)) {
                    return false
                }

                while (queue.size >= MAX_QUEUE_SIZE) {
                    val evicted = queue.poll()
                    if (evicted != null) {
                        dedupSet.remove(getDedupKey(evicted))
                    }
                }

                queue.add(data)
                dedupSet.add(dedupKey)

                try {
                    Log.d(TAG, "Captured: $packageName - ${NotificationRedactor.redactTitle(title)}")
                } catch (_: Throwable) {
                    // Safe log fallback for non-Android unit test runtimes
                }

                return true
            }
        }

        /**
         * Drains all non-expired notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue is empty.
         */
        fun drainQueue(now: Long = System.currentTimeMillis()): List<NotificationData> {
            synchronized(lock) {
                val result = mutableListOf<NotificationData>()
                val iterator = queue.iterator()
                while (iterator.hasNext()) {
                    val item = iterator.next()
                    if (now - item.timestamp <= MAX_AGE_MS) {
                        result.add(item)
                    }
                }
                queue.clear()
                dedupSet.clear()
                return result
            }
        }

        /**
         * Clears the queue and resets internal state (for testing/diagnostics).
         */
        fun clearQueue() {
            synchronized(lock) {
                queue.clear()
                dedupSet.clear()
                idCounter.set(0L)
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

    private fun addSbnToQueue(sbn: StatusBarNotification, now: Long = System.currentTimeMillis()) {
        try {
            val extras = sbn.notification?.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing || (sbn.notification != null && (sbn.notification.flags and android.app.Notification.FLAG_ONGOING_EVENT) != 0)
            val packageName = sbn.packageName ?: "unknown"
            val timestamp = if (sbn.postTime > 0) sbn.postTime else now
            val category = sbn.notification?.category

            enqueueNotification(
                packageName = packageName,
                title = title,
                content = text,
                timestamp = timestamp,
                category = category,
                isOngoing = isOngoing,
                now = now
            )
        } catch (e: Exception) {
            try {
                Log.e(TAG, "Error capturing/adding notification", e)
            } catch (_: Throwable) {}
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        addSbnToQueue(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        try {
            val packageName = sbn.packageName ?: "unknown"
            val title = sbn.notification?.extras?.getCharSequence("android.title")?.toString() ?: ""
            try {
                Log.d(TAG, "Removed: $packageName - ${NotificationRedactor.redactTitle(title)}")
            } catch (_: Throwable) {}
        } catch (e: Exception) {
            try {
                Log.e(TAG, "Error logging notification removal", e)
            } catch (_: Throwable) {}
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        try {
            Log.i(TAG, "NotificationCollectorService connected")
        } catch (_: Throwable) {}
        try {
            val activeNotifs = activeNotifications
            if (activeNotifs != null) {
                try {
                    Log.d(TAG, "Syncing ${activeNotifs.size} existing notifications from panel")
                } catch (_: Throwable) {}
                for (sbn in activeNotifs) {
                    addSbnToQueue(sbn)
                }
            }
        } catch (e: Exception) {
            try {
                Log.e(TAG, "Error fetching active notifications on connect", e)
            } catch (_: Throwable) {}
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        try {
            Log.w(TAG, "NotificationCollectorService disconnected")
        } catch (_: Throwable) {}
    }
}
