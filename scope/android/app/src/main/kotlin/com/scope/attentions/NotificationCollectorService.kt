package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are placed in a static [queue].
 *
 * Two-phase transactional IPC model:
 *   1. Flutter fetches pending notifications via [fetchPendingBatch]. Notifications are
 *      packaged into a [NotificationBatch] with a unique transaction ID and stored in
 *      [pendingBatches].
 *   2. After Flutter successfully persists the notifications in local database storage,
 *      it calls [acknowledgeBatch] with the transaction ID to purge the batch from native memory.
 *   3. If unacknowledged within 30 seconds, [rollbackExpiredBatches] returns the batch items
 *      to [queue] for re-delivery.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Default maximum items per batch to prevent MethodChannel buffer overflow. */
        const val MAX_BATCH_SIZE = 100

        /** Expiry timeout for unacknowledged pending batches (30 seconds). */
        const val BATCH_TIMEOUT_MS = 30_000L

        /** Thread-safe active queue of captured notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Thread-safe registry of pending notification batches waiting for Flutter acknowledgement. */
        private val pendingBatches = ConcurrentHashMap<String, NotificationBatch>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /** Background scheduler for automatic 30-second expiry checks. */
        private val scheduler: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor()

        init {
            scheduler.scheduleAtFixedRate({
                try {
                    rollbackExpiredBatches()
                } catch (e: Throwable) {
                    // Suppress exceptions to keep scheduler running
                }
            }, 1, 1, TimeUnit.SECONDS)
        }

        private fun logD(tag: String, msg: String) {
            try { Log.d(tag, msg) } catch (_: Throwable) {}
        }

        private fun logW(tag: String, msg: String) {
            try { Log.w(tag, msg) } catch (_: Throwable) {}
        }

        private fun logE(tag: String, msg: String, tr: Throwable? = null) {
            try {
                if (tr != null) Log.e(tag, msg, tr) else Log.e(tag, msg)
            } catch (_: Throwable) {}
        }

        private fun logI(tag: String, msg: String) {
            try { Log.i(tag, msg) } catch (_: Throwable) {}
        }

        /**
         * Fetches up to [limit] (max [MAX_BATCH_SIZE]) notifications from the active queue,
         * assigns a unique transaction batch ID, and moves them to [pendingBatches].
         * Returns null if no notifications are available.
         */
        @Synchronized
        fun fetchPendingBatch(limit: Int = MAX_BATCH_SIZE): NotificationBatch? {
            rollbackExpiredBatches()

            if (queue.isEmpty()) return null

            val effectiveLimit = limit.coerceAtMost(MAX_BATCH_SIZE)
            val batchItems = mutableListOf<NotificationData>()

            for (i in 0 until effectiveLimit) {
                val item = queue.poll() ?: break
                batchItems.add(item)
            }

            if (batchItems.isEmpty()) return null

            val batchId = "tx_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}"
            val batch = NotificationBatch(
                batchId = batchId,
                notifications = batchItems,
                timestamp = System.currentTimeMillis()
            )

            pendingBatches[batchId] = batch
            logD(TAG, "Created pending batch $batchId with ${batchItems.size} items.")
            return batch
        }

        /**
         * Acknowledges local persistence of a transaction batch.
         * Purges the batch from native memory upon receipt from Flutter.
         * Returns true if the batch was found and purged, false otherwise.
         */
        @Synchronized
        fun acknowledgeBatch(batchId: String): Boolean {
            rollbackExpiredBatches()
            val removed = pendingBatches.remove(batchId)
            if (removed != null) {
                logD(TAG, "Acknowledged and purged batch $batchId (${removed.notifications.size} items).")
                return true
            }
            logW(TAG, "Failed to acknowledge batch $batchId: not found or already expired.")
            return false
        }

        /**
         * Returns pending batch items to the active queue if no acknowledgement
         * was received within 30 seconds.
         */
        @Synchronized
        fun rollbackExpiredBatches() {
            val now = System.currentTimeMillis()
            val expiredBatchIds = mutableListOf<String>()

            for ((batchId, batch) in pendingBatches) {
                if (now - batch.timestamp >= BATCH_TIMEOUT_MS) {
                    expiredBatchIds.add(batchId)
                }
            }

            for (batchId in expiredBatchIds) {
                val batch = pendingBatches.remove(batchId) ?: continue
                logW(TAG, "Batch $batchId expired after 30s. Rolling back ${batch.notifications.size} items to active queue.")
                queue.addAll(batch.notifications)
            }
        }

        /**
         * Non-destructive peek method allowing Flutter or diagnostics to monitor queue length.
         */
        fun peekQueueCount(): Int {
            rollbackExpiredBatches()
            return queue.size
        }

        /**
         * Returns total unacknowledged notifications count (active queue + pending batches).
         */
        fun totalPendingCount(): Int {
            rollbackExpiredBatches()
            val pendingCount = pendingBatches.values.sumOf { it.notifications.size }
            return queue.size + pendingCount
        }

        /**
         * Legacy method: drains all notifications from the queue and returns them.
         * Deprecated in favor of two-phase [fetchPendingBatch] and [acknowledgeBatch].
         */
        @Synchronized
        fun drainQueue(): List<NotificationData> {
            rollbackExpiredBatches()
            val result = mutableListOf<NotificationData>()
            while (true) {
                val item = queue.poll() ?: break
                result.add(item)
            }
            return result
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int = peekQueueCount()

        /**
         * Helper for testing/cleanup: clears active queue and pending batches.
         */
        @Synchronized
        fun clearAll() {
            queue.clear()
            pendingBatches.clear()
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
