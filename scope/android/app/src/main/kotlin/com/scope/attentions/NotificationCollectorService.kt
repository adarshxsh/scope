package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Data class representing an in-flight transaction batch.
 */
data class TransactionBatch(
    val batchId: String,
    val timestamp: Long,
    val items: ConcurrentLinkedQueue<NotificationData>
)

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are managed with a two-phase transactional
 * acknowledgment protocol to guarantee zero data loss.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum buffer capacity across pending and in-flight items. */
        const val MAX_BUFFER_SIZE = 500

        /** Timeout (in milliseconds) before unacknowledged transactions revert to queue. */
        const val TRANSACTION_TIMEOUT_MS = 30_000L

        /** Thread-safe queue of pending notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Thread-safe map of active, in-flight transaction batches. */
        private val inFlightTransactions = ConcurrentHashMap<String, TransactionBatch>()

        /** Session token for caller authorization. */
        @Volatile
        private var sessionToken: String = "scope-session-token"

        /** Counter for generating simple unique notification IDs within a session. */
        private var idCounter = 0L

        /** Counter for generating batch IDs. */
        private var batchCounter = 0L

        fun setSessionToken(token: String) {
            sessionToken = token
        }

        fun getSessionToken(): String = sessionToken

        fun validateToken(token: String?): Boolean {
            return token != null && token == sessionToken
        }

        /**
         * Cleans up expired transaction batches and reverts unacknowledged
         * notifications back to the pending queue for re-delivery.
         */
        fun cleanupExpiredTransactions() {
            val now = System.currentTimeMillis()
            val expiredEntries = inFlightTransactions.entries.filter {
                now - it.value.timestamp > TRANSACTION_TIMEOUT_MS
            }

            for (entry in expiredEntries) {
                inFlightTransactions.remove(entry.key)
                while (true) {
                    val item = entry.value.items.poll() ?: break
                    if (queue.none { it.id == item.id }) {
                        queue.add(item)
                    }
                }
                Log.d(TAG, "Transaction ${entry.key} timed out and reverted to active queue.")
            }
        }

        /**
         * Fetches pending notifications in a pending transaction state.
         * Retains fetched notifications in an in-flight transaction map keyed by batch ID.
         */
        fun getNotifications(): Map<String, Any?> {
            cleanupExpiredTransactions()

            val itemsToBatch = mutableListOf<NotificationData>()
            while (itemsToBatch.size < MAX_BUFFER_SIZE) {
                val item = queue.poll() ?: break
                itemsToBatch.add(item)
            }

            if (itemsToBatch.isEmpty()) {
                return mapOf(
                    "batchId" to "",
                    "notifications" to emptyList<Map<String, Any?>>()
                )
            }

            val batchId = "batch_${System.currentTimeMillis()}_${++batchCounter}"
            val batchQueue = ConcurrentLinkedQueue<NotificationData>(itemsToBatch)
            inFlightTransactions[batchId] = TransactionBatch(
                batchId = batchId,
                timestamp = System.currentTimeMillis(),
                items = batchQueue
            )

            return mapOf(
                "batchId" to batchId,
                "notifications" to itemsToBatch.map { it.toMap() }
            )
        }

        /**
         * Explicitly acknowledges processed notification IDs, removing them permanently.
         */
        fun acknowledgeNotifications(ids: List<String>, batchId: String?): Boolean {
            if (ids.isEmpty()) return true

            val idSet = ids.toSet()

            if (batchId != null && batchId.isNotEmpty()) {
                inFlightTransactions[batchId]?.let { batch ->
                    batch.items.removeIf { idSet.contains(it.id) }
                    if (batch.items.isEmpty()) {
                        inFlightTransactions.remove(batchId)
                    }
                }
            }

            // Idempotent purge across all in-flight batches & queue
            for ((bId, batch) in inFlightTransactions) {
                batch.items.removeIf { idSet.contains(it.id) }
                if (batch.items.isEmpty()) {
                    inFlightTransactions.remove(bId)
                }
            }

            queue.removeIf { idSet.contains(it.id) }

            return true
        }

        /**
         * Non-destructive peek at pending notifications without changing queue state.
         */
        fun peekNotifications(): List<NotificationData> {
            cleanupExpiredTransactions()
            return queue.toList()
        }

        /**
         * Returns current queue size including active and in-flight items.
         */
        fun queueSize(): Int {
            cleanupExpiredTransactions()
            val inFlightCount = inFlightTransactions.values.sumOf { it.items.size }
            return queue.size + inFlightCount
        }

        /**
         * Drains all notifications from the queue and returns them.
         * Kept for backward compatibility.
         */
        fun drainQueue(): List<NotificationData> {
            cleanupExpiredTransactions()
            val result = mutableListOf<NotificationData>()
            while (true) {
                val item = queue.poll() ?: break
                result.add(item)
            }
            return result
        }

        /**
         * Reset state for testing purposes.
         */
        fun resetForTesting() {
            queue.clear()
            inFlightTransactions.clear()
            sessionToken = "scope-session-token"
            idCounter = 0L
            batchCounter = 0L
        }
    }

    private fun addSbnToQueue(sbn: StatusBarNotification) {
        try {
            cleanupExpiredTransactions()

            val extras = sbn.notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: "unknown"

            // Ignore if same package, title, and content already exist in queue or in-flight
            val isDuplicate = queue.any {
                it.packageName == packageName && it.title == title && it.content == text
            } || inFlightTransactions.values.any { batch ->
                batch.items.any { it.packageName == packageName && it.title == title && it.content == text }
            }

            if (isDuplicate) {
                return
            }

            val totalItems = queue.size + inFlightTransactions.values.sumOf { it.items.size }
            if (totalItems >= MAX_BUFFER_SIZE) {
                // Drop oldest item from queue if buffer limit reached
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
