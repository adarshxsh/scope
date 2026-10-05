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
 *   - Bounded static queue (MAX_QUEUE_SIZE = 250) with drop-oldest eviction policy.
 *   - O(1) deduplication tracking using a HashSet signature map to avoid O(N^2) overhead.
 *   - AtomicLong for thread-safe session ID generation.
 *   - Ingestion filtering excluding ongoing alerts and noise categories (progress, navigation, service, sys, system, transport, status).
 *   - PII log sanitization via [NotificationRedactor] to prevent sensitive logcat exposure.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum capacity for the native notification queue to prevent memory leaks. */
        const val MAX_QUEUE_SIZE = 250

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

        /**
         * Enqueues a notification with input validation, filtering, O(1) deduplication,
         * and drop-oldest FIFO queue bounding.
         *
         * @return true if enqueued successfully, false if rejected (duplicate/filtered).
         */
        fun enqueueNotification(
            packageName: String,
            title: String,
            content: String,
            timestamp: Long,
            category: String?,
            isOngoing: Boolean
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

            val dedupKey = "$packageName:$title:$content"

            synchronized(lock) {
                // O(1) duplicate check
                if (dedupSet.contains(dedupKey)) {
                    return false
                }

                // Drop-oldest eviction if queue reaches max capacity
                while (queue.size >= MAX_QUEUE_SIZE) {
                    val evicted = queue.poll()
                    if (evicted != null) {
                        val evictedKey = "${evicted.packageName}:${evicted.title}:${evicted.content}"
                        dedupSet.remove(evictedKey)
                    }
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

                queue.add(data)
                dedupSet.add(dedupKey)

                try {
                    Log.d(TAG, "Captured: $packageName - ${NotificationRedactor.redact(title)}")
                } catch (_: Throwable) {
                    // Safe log fallback for non-Android unit test runtimes
                }

                return true
            }
        }

        /**
         * Drains all notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue is empty.
         */
        fun drainQueue(): List<NotificationData> {
            synchronized(lock) {
                val result = ArrayList<NotificationData>(queue)
                queue.clear()
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

        /**
         * Clears all items from the queue and deduplication set (diagnostic/test cleanup).
         */
        fun clearQueue() {
            synchronized(lock) {
                queue.clear()
                dedupSet.clear()
            }
        }
    }

    private fun addSbnToQueue(sbn: StatusBarNotification) {
        try {
            val extras = sbn.notification?.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing || (sbn.notification != null && (sbn.notification.flags and android.app.Notification.FLAG_ONGOING_EVENT) != 0)
            val packageName = sbn.packageName ?: "unknown"
            val category = sbn.notification?.category

            enqueueNotification(
                packageName = packageName,
                title = title,
                content = text,
                timestamp = sbn.postTime,
                category = category,
                isOngoing = isOngoing
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
                Log.d(TAG, "Removed: $packageName - ${NotificationRedactor.redact(title)}")
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
