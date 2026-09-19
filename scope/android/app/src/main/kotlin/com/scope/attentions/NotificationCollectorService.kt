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
 * Captured notifications are placed in a thread-safe, bounded static [queue]
 * which is drained by [MainActivity] when Flutter requests them via MethodChannel.
 *
 * Fortifications:
 *   - Bounded queue capacity (default 500) to prevent native memory leaks when Flutter is paused/delayed.
 *   - O(1) duplicate lookup using a hash set rather than O(N) linear scans.
 *   - Redacted logging: cleartext notification titles and contents are NEVER logged to logcat.
 *   - Telemetry metrics for monitoring captured, duplicate, and overflow evicted notification counts.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"
        const val DEFAULT_MAX_QUEUE_CAPACITY = 500

        /** Capacity limit for the native notification queue. */
        @Volatile
        private var maxQueueCapacity = DEFAULT_MAX_QUEUE_CAPACITY

        /** Lock object for thread-safe queue and deduplication operations. */
        private val lock = Any()

        /** Internal queue storing captured notifications in FIFO order. */
        private val queue = ArrayDeque<NotificationData>()

        /** O(1) deduplication lookup set for active queued notification keys. */
        private val seenKeys = HashSet<String>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /** Telemetry metrics */
        private var totalCapturedCount = 0L
        private var duplicateDroppedCount = 0L
        private var overflowEvictedCount = 0L
        private var lastDrainedTimestamp = 0L

        /**
         * Helper to build deduplication key from package name, title, and content.
         */
        private fun makeDedupKey(packageName: String, title: String, content: String): String {
            return "$packageName::$title::$content"
        }

        /**
         * Enqueues a notification with duplicate detection and capacity bounding.
         * Returns true if successfully enqueued, false if dropped as duplicate.
         */
        fun enqueueNotification(
            packageName: String,
            title: String,
            content: String,
            category: String? = null,
            isOngoing: Boolean = false,
            timestamp: Long = System.currentTimeMillis()
        ): Boolean {
            synchronized(lock) {
                val dedupKey = makeDedupKey(packageName, title, content)
                if (seenKeys.contains(dedupKey)) {
                    duplicateDroppedCount++
                    Log.d(TAG, "Duplicate notification dropped for pkg=$packageName")
                    return false
                }

                // Evict oldest notifications if queue size reaches maxQueueCapacity
                while (queue.size >= maxQueueCapacity) {
                    val evicted = queue.removeFirst()
                    seenKeys.remove(makeDedupKey(evicted.packageName, evicted.title, evicted.content))
                    overflowEvictedCount++
                    Log.w(TAG, "Queue capacity reached ($maxQueueCapacity), evicted oldest notification")
                }

                val data = NotificationData(
                    id = "notif_${++idCounter}",
                    packageName = packageName,
                    title = title,
                    content = content,
                    timestamp = timestamp,
                    category = category,
                    isOngoing = isOngoing
                )

                queue.addLast(data)
                seenKeys.add(dedupKey)
                totalCapturedCount++

                // Sanitize log: log non-sensitive metadata only (pkg, id, queue size)
                Log.d(TAG, "Captured notification id=${data.id} pkg=$packageName queueSize=${queue.size}")
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
                seenKeys.clear()
                lastDrainedTimestamp = System.currentTimeMillis()
                return result
            }
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int = synchronized(lock) { queue.size }

        /**
         * Sets maximum queue capacity. Evicts oldest items if current size exceeds new capacity.
         */
        fun setMaxQueueCapacity(capacity: Int) {
            synchronized(lock) {
                if (capacity > 0) {
                    maxQueueCapacity = capacity
                    while (queue.size > maxQueueCapacity) {
                        val evicted = queue.removeFirst()
                        seenKeys.remove(makeDedupKey(evicted.packageName, evicted.title, evicted.content))
                        overflowEvictedCount++
                    }
                }
            }
        }

        /**
         * Returns system telemetry metrics.
         */
        fun getTelemetry(): Map<String, Any> = synchronized(lock) {
            return mapOf(
                "totalCapturedCount" to totalCapturedCount,
                "duplicateDroppedCount" to duplicateDroppedCount,
                "overflowEvictedCount" to overflowEvictedCount,
                "currentQueueSize" to queue.size,
                "maxQueueCapacity" to maxQueueCapacity,
                "lastDrainedTimestamp" to lastDrainedTimestamp
            )
        }

        /**
         * Resets state (queue, deduplication set, telemetry) for unit testing.
         */
        fun resetForTest() {
            synchronized(lock) {
                queue.clear()
                seenKeys.clear()
                idCounter = 0L
                totalCapturedCount = 0L
                duplicateDroppedCount = 0L
                overflowEvictedCount = 0L
                lastDrainedTimestamp = 0L
                maxQueueCapacity = DEFAULT_MAX_QUEUE_CAPACITY
            }
        }
    }

    private fun addSbnToQueue(sbn: StatusBarNotification) {
        try {
            val extras = sbn.notification?.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: "unknown"
            val category = sbn.notification?.category
            val timestamp = sbn.postTime

            enqueueNotification(
                packageName = packageName,
                title = title,
                content = text,
                category = category,
                isOngoing = isOngoing,
                timestamp = timestamp
            )
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
        val removedTitle = sbn.notification?.extras?.getCharSequence("android.title")?.toString()
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
