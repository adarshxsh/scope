package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicLong

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are placed in a static [queue] which is accessed
 * by [MainActivity] when Flutter requests them via MethodChannel.
 *
 * Security guardrails:
 *   - Access requires a valid session token obtained via [getSessionToken].
 *   - Supports two-phase pull protocol ([peekQueue] and [acknowledgeQueue])
 *     as well as token-authorized queue drainage ([drainQueue]).
 *   - Tracks authorized and unauthorized access metrics for system auditing.
 *   - Redacts personal data and notification content from logs.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum allowed queue size to prevent unbounded memory growth. */
        const val MAX_QUEUE_SIZE = 100

        /** Maximum time-to-live for queued notifications (15 minutes in milliseconds). */
        const val MAX_AGE_MS = 15 * 60 * 1000L

        /** Thread-safe queue of captured notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /** Current active session token for MethodChannel authorization. */
        @Volatile
        private var activeSessionToken: String? = null

        /** Audit counters. */
        private val authorizedAccessCount = AtomicLong(0L)
        private val unauthorizedAccessCount = AtomicLong(0L)

        private fun safeLogW(tag: String, message: String) {
            try {
                Log.w(tag, message)
            } catch (_: Throwable) {
                // Ignore Android Log stub exception in desktop JVM unit tests
            }
        }

        private fun safeLogD(tag: String, message: String) {
            try {
                Log.d(tag, message)
            } catch (_: Throwable) {
                // Ignore Android Log stub exception in desktop JVM unit tests
            }
        }

        private fun safeLogI(tag: String, message: String) {
            try {
                Log.i(tag, message)
            } catch (_: Throwable) {
                // Ignore Android Log stub exception in desktop JVM unit tests
            }
        }

        private fun safeLogE(tag: String, message: String, throwable: Throwable? = null) {
            try {
                if (throwable != null) {
                    Log.e(tag, message, throwable)
                } else {
                    Log.e(tag, message)
                }
            } catch (_: Throwable) {
                // Ignore Android Log stub exception in desktop JVM unit tests
            }
        }

        /**
         * Generates or retrieves the active session authorization token.
         */
        @Synchronized
        fun getSessionToken(): String {
            if (activeSessionToken == null) {
                activeSessionToken = UUID.randomUUID().toString()
            }
            return activeSessionToken!!
        }

        /**
         * Validates the provided token against the active session token.
         */
        fun validateToken(token: String?): Boolean {
            val currentToken = activeSessionToken
            if (currentToken == null || token.isNullOrEmpty()) {
                return false
            }
            return currentToken == token
        }

        /**
         * Peeks all notifications currently in the queue without removing them.
         * Requires a valid [token].
         */
        fun peekQueue(token: String?): List<NotificationData> {
            if (!validateToken(token)) {
                unauthorizedAccessCount.incrementAndGet()
                safeLogW(TAG, "Unauthorized MethodChannel peekQueue attempt blocked")
                throw SecurityException("Unauthorized access attempt: invalid session token")
            }
            authorizedAccessCount.incrementAndGet()
            return queue.toList()
        }

        /**
         * Acknowledges and removes specific notifications from the queue by ID.
         * Requires a valid [token]. Returns list of acknowledged IDs.
         */
        fun acknowledgeQueue(token: String?, ids: List<String>): List<String> {
            if (!validateToken(token)) {
                unauthorizedAccessCount.incrementAndGet()
                safeLogW(TAG, "Unauthorized MethodChannel acknowledgeQueue attempt blocked")
                throw SecurityException("Unauthorized access attempt: invalid session token")
            }
            authorizedAccessCount.incrementAndGet()
            if (ids.isEmpty()) return emptyList()

            val idsSet = ids.toSet()
            val acknowledgedIds = mutableListOf<String>()
            val iterator = queue.iterator()
            while (iterator.hasNext()) {
                val item = iterator.next()
                if (idsSet.contains(item.id)) {
                    iterator.remove()
                    acknowledgedIds.add(item.id)
                }
            }
            return acknowledgedIds
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
         * Drains all non-expired notifications from the queue and returns them.
         * Requires a valid [token].
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue is empty.
         */
        fun drainQueue(token: String?, now: Long = System.currentTimeMillis()): List<NotificationData> {
            if (!validateToken(token)) {
                unauthorizedAccessCount.incrementAndGet()
                safeLogW(TAG, "Unauthorized MethodChannel drainQueue attempt blocked")
                throw SecurityException("Unauthorized access attempt: invalid session token")
            }
            authorizedAccessCount.incrementAndGet()
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
         * Drains all non-expired notifications from the queue using internal session token.
         * Maintained for internal service usage and backward compatibility.
         */
        fun drainQueue(now: Long = System.currentTimeMillis()): List<NotificationData> {
            return drainQueue(getSessionToken(), now)
        }

        /**
         * Returns current diagnostic audit metrics.
         */
        fun getAuditMetrics(): Map<String, Any> {
            return mapOf(
                "authorizedAccessCount" to authorizedAccessCount.get(),
                "unauthorizedAccessCount" to unauthorizedAccessCount.get(),
                "queueSize" to queue.size
            )
        }

        /**
         * Clears the queue and resets internal state (for testing).
         */
        fun clearQueue() {
            queue.clear()
            idCounter = 0L
        }

        /**
         * Clears all queue items and resets session token and audit metrics (for testing).
         */
        fun resetForTesting() {
            clearQueue()
            activeSessionToken = null
            authorizedAccessCount.set(0L)
            unauthorizedAccessCount.set(0L)
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int = queue.size
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
            safeLogD(TAG, "Captured: ${data.packageName} - ${NotificationRedactor.redactTitle(data.title)}")
        } catch (e: Exception) {
            safeLogE(TAG, "Error capturing/adding notification", e)
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
        safeLogD(TAG, "Removed: ${sbn.packageName} - ${NotificationRedactor.redactTitle(removedTitle)}")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        safeLogI(TAG, "NotificationCollectorService connected")
        try {
            val activeNotifs = activeNotifications
            if (activeNotifs != null) {
                safeLogD(TAG, "Syncing ${activeNotifs.size} existing notifications from panel")
                for (sbn in activeNotifs) {
                    addSbnToQueue(sbn)
                }
            }
        } catch (e: Exception) {
            safeLogE(TAG, "Error fetching active notifications on connect", e)
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        safeLogW(TAG, "NotificationCollectorService disconnected")
    }
}
