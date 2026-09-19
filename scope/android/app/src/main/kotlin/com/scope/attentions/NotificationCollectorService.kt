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
         * Drains all notifications from the queue and returns them.
         * Requires a valid [token].
         * After this call, the queue is empty.
         */
        fun drainQueue(token: String?): List<NotificationData> {
            if (!validateToken(token)) {
                unauthorizedAccessCount.incrementAndGet()
                safeLogW(TAG, "Unauthorized MethodChannel drainQueue attempt blocked")
                throw SecurityException("Unauthorized access attempt: invalid session token")
            }
            authorizedAccessCount.incrementAndGet()
            val result = mutableListOf<NotificationData>()
            while (true) {
                val item = queue.poll() ?: break
                result.add(item)
            }
            return result
        }

        /**
         * Drains all notifications from the queue using internal session token.
         * Maintained for internal service usage and backward compatibility.
         */
        fun drainQueue(): List<NotificationData> {
            return drainQueue(getSessionToken())
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
         * Clears all queue items and resets session token (for testing).
         */
        fun resetForTesting() {
            queue.clear()
            activeSessionToken = null
            authorizedAccessCount.set(0L)
            unauthorizedAccessCount.set(0L)
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int = queue.size
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
            safeLogD(TAG, "Captured notification from package: ${data.packageName}")
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
        safeLogD(TAG, "Notification removed for package: ${sbn.packageName}")
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
