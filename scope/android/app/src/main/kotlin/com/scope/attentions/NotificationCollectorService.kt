package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Data class representing a batch of pending notifications sent across MethodChannel.
 */
data class NotificationBatch(
    val batchId: String,
    val notifications: List<NotificationData>,
    val createdAt: Long = System.currentTimeMillis()
)

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are placed in a static pending queue and dispatched
 * in tagged batches to Flutter via MethodChannel.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum allowed queue size to prevent unbounded memory growth. */
        const val MAX_QUEUE_SIZE = 100

        /** Alias for MAX_QUEUE_SIZE for batch/queue capacity references. */
        const val MAX_QUEUE_CAPACITY = MAX_QUEUE_SIZE

        /** Maximum time-to-live for queued notifications (15 minutes in milliseconds). */
        const val MAX_AGE_MS = 15 * 60 * 1000L

        /** Default batch capacity (500 items). */
        const val MAX_BATCH_CAPACITY = 500

        /** Default batch timeout (5 minutes in milliseconds). */
        const val DEFAULT_TIMEOUT_MS = 5 * 60 * 1000L

        /** Thread-safe queue of captured pending notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** In-flight batches waiting for explicit Flutter acknowledgement. */
        private val inFlightBatches = ConcurrentHashMap<String, NotificationBatch>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /** Counter for batch sequence numbers. */
        private var batchIdCounter = 0L

        private fun logD(tag: String, msg: String) {
            try { Log.d(tag, msg) } catch (_: Throwable) { println("[$tag DEBUG] $msg") }
        }
        private fun logW(tag: String, msg: String) {
            try { Log.w(tag, msg) } catch (_: Throwable) { println("[$tag WARN] $msg") }
        }
        private fun logE(tag: String, msg: String, tr: Throwable? = null) {
            try { Log.e(tag, msg, tr) } catch (_: Throwable) { println("[$tag ERROR] $msg") }
        }
        private fun logI(tag: String, msg: String) {
            try { Log.i(tag, msg) } catch (_: Throwable) { println("[$tag INFO] $msg") }
        }

        /**
         * Removes entries older than [MAX_AGE_MS] from the queue.
         */
        fun pruneExpired(now: Long = System.currentTimeMillis()) {
            queue.removeIf { now - it.timestamp > MAX_AGE_MS }
        }

        /**
         * Adds a [NotificationData] item to the queue after pruning expired items
         * and enforcing maximum queue capacity.
         */
        fun addNotification(data: NotificationData, now: Long = System.currentTimeMillis()) {
            pruneExpired(now)

            // Do not add item if it is already expired relative to current time
            if (now - data.timestamp > MAX_AGE_MS) {
                return
            }

            // Ignore if same package, title, and content already exist in queue
            val isDuplicate = queue.any {
                it.packageName == data.packageName && it.title == data.title && it.content == data.content
            }
            if (isDuplicate) {
                return
            }

            // Evict oldest notification if queue reaches MAX_QUEUE_SIZE before adding new items
            while (queue.size >= MAX_QUEUE_SIZE) {
                queue.poll()
            }

            queue.add(data)
        }

        /**
         * Clears all pending and in-flight notifications and resets counters (for testing/resets).
         */
        @Synchronized
        fun clearQueue() {
            queue.clear()
            inFlightBatches.clear()
            idCounter = 0L
            batchIdCounter = 0L
        }

        /**
         * Releases in-flight batches that have timed out (older than [timeoutMs]).
         */
        @Synchronized
        fun processTimeouts(
            timeoutMs: Long = DEFAULT_TIMEOUT_MS,
            currentTime: Long = System.currentTimeMillis()
        ) {
            val expiredIds = mutableListOf<String>()
            for ((id, batch) in inFlightBatches) {
                if (currentTime - batch.createdAt >= timeoutMs) {
                    expiredIds.add(id)
                }
            }
            for (id in expiredIds) {
                val expiredBatch = inFlightBatches.remove(id) ?: continue
                logW(TAG, "Batch $id timed out after ${timeoutMs}ms; returning ${expiredBatch.notifications.size} items to pending queue")
                for (item in expiredBatch.notifications) {
                    if (currentTime - item.timestamp <= MAX_AGE_MS) {
                        queue.add(item)
                    }
                }
            }
        }

        /**
         * Gets a tagged notification batch.
         *
         * Re-delivers existing active in-flight batch if present and not timed out.
         * Otherwise creates a new batch polling up to [maxBatchCapacity] items from queue.
         */
        @Synchronized
        fun getBatch(
            maxBatchCapacity: Int = MAX_BATCH_CAPACITY,
            timeoutMs: Long = DEFAULT_TIMEOUT_MS,
            currentTime: Long = System.currentTimeMillis()
        ): NotificationBatch {
            pruneExpired(currentTime)
            processTimeouts(timeoutMs, currentTime)

            // Re-deliver active in-flight batch if one exists
            val activeBatch = inFlightBatches.values.firstOrNull()
            if (activeBatch != null) {
                val validNotifications = activeBatch.notifications.filter { currentTime - it.timestamp <= MAX_AGE_MS }
                if (validNotifications.isEmpty()) {
                    inFlightBatches.remove(activeBatch.batchId)
                } else {
                    return activeBatch.copy(notifications = validNotifications)
                }
            }

            if (queue.isEmpty()) {
                return NotificationBatch(batchId = "", notifications = emptyList(), createdAt = currentTime)
            }

            val batchItems = mutableListOf<NotificationData>()
            while (batchItems.size < maxBatchCapacity) {
                val item = queue.poll() ?: break
                if (currentTime - item.timestamp <= MAX_AGE_MS) {
                    batchItems.add(item)
                }
            }

            if (batchItems.isEmpty()) {
                return NotificationBatch(batchId = "", notifications = emptyList(), createdAt = currentTime)
            }

            val batchId = "batch_${++batchIdCounter}_${UUID.randomUUID()}"
            val batch = NotificationBatch(batchId = batchId, notifications = batchItems, createdAt = currentTime)
            inFlightBatches[batchId] = batch
            return batch
        }

        /**
         * Acknowledges processing of a notification batch by ID.
         */
        @Synchronized
        fun acknowledgeBatch(batchId: String?): Boolean {
            if (batchId.isNullOrEmpty()) return false
            val removed = inFlightBatches.remove(batchId)
            if (removed != null) {
                logD(TAG, "Acknowledged batch $batchId containing ${removed.notifications.size} items")
                return true
            }
            return false
        }

        /**
         * Non-destructive inspection of pending queue items.
         */
        fun peekQueue(): List<NotificationData> = queue.toList()

        /**
         * Returns the current pending queue size (for diagnostics).
         */
        fun queueSize(): Int = queue.size

        /**
         * Alias for queueSize() for consistency.
         */
        fun getQueueSize(): Int = queueSize()

        /**
         * Helper for unit tests to enqueue notification data.
         */
        fun enqueueForTesting(data: NotificationData) {
            addNotification(data)
        }

        /**
         * Drains all non-expired notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications without batching.
         * After this call, the returned batch is acknowledged.
         */
        @Synchronized
        fun drainQueue(now: Long = System.currentTimeMillis()): List<NotificationData> {
            val batch = getBatch(currentTime = now)
            acknowledgeBatch(batch.batchId)
            return batch.notifications
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
}
