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

        /** Thread-safe queue of captured pending notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** In-flight batches waiting for explicit Flutter acknowledgement. */
        private val inFlightBatches = ConcurrentHashMap<String, NotificationBatch>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /** Counter for batch sequence numbers. */
        private var batchIdCounter = 0L

        /** Default batch capacity (500 items). */
        const val MAX_BATCH_CAPACITY = 500

        /** Maximum allowed pending queue capacity. */
        const val MAX_QUEUE_CAPACITY = 500

        /** Default batch timeout (5 minutes in milliseconds). */
        const val DEFAULT_TIMEOUT_MS = 5 * 60 * 1000L

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
         * Clears all pending and in-flight notifications (for testing/resets).
         */
        @Synchronized
        fun clearQueue() {
            queue.clear()
            inFlightBatches.clear()
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
                    queue.add(item)
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
            processTimeouts(timeoutMs, currentTime)

            // Re-deliver active in-flight batch if one exists
            val activeBatch = inFlightBatches.values.firstOrNull()
            if (activeBatch != null) {
                return activeBatch
            }

            if (queue.isEmpty()) {
                return NotificationBatch(batchId = "", notifications = emptyList(), createdAt = currentTime)
            }

            val batchItems = mutableListOf<NotificationData>()
            while (batchItems.size < maxBatchCapacity) {
                val item = queue.poll() ?: break
                batchItems.add(item)
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
            queue.add(data)
        }

        /**
         * Drains all notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue is empty.
         */
        @Synchronized
        fun drainQueue(): List<NotificationData> {
            val batch = getBatch()
            acknowledgeBatch(batch.batchId)
            return batch.notifications
        }
    }

    private fun addSbnToQueue(sbn: StatusBarNotification) {
        try {
            val extras = sbn.notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: "unknown"

            // Ignore if same package, title, and content already exist in queue
            val isDuplicate = queue.any {
                it.packageName == packageName && it.title == title && it.content == text
            }
            if (isDuplicate) {
                return
            }

            // Cap pending queue
            while (queue.size >= MAX_QUEUE_CAPACITY) {
                queue.poll()
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

            queue.add(data)
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
