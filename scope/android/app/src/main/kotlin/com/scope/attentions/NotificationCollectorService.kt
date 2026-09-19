package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicLong

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are placed in a static [queue] which is drained
 * by [MainActivity] when Flutter requests them via MethodChannel.
 *
 * Design decisions:
 *   - Uses a static ConcurrentLinkedQueue (thread-safe, lock-free) bounded to [MAX_QUEUE_SIZE].
 *   - Thread-safe [idCounter] using [AtomicLong] prevents ID collision across background threads.
 *   - Input sanitization enforces string length boundaries and null safety.
 *   - Zero cleartext PII logging to protect user privacy.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum capacity for in-memory notification queue to bound RAM usage. */
        private const val MAX_QUEUE_SIZE = 500

        /** Thread-safe queue of captured notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Thread-safe counter for generating unique IDs across background threads. */
        private val idCounter = AtomicLong(System.currentTimeMillis())

        /** Total notifications evicted/dropped due to queue overflow. */
        private val droppedCount = AtomicLong(0)

        /**
         * Drains all notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue is empty.
         */
        fun drainQueue(): List<NotificationData> {
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
        fun queueSize(): Int = queue.size

        /**
         * Returns queue diagnostic stats without exposing cleartext PII.
         */
        fun getQueueStats(): Map<String, Any> {
            return mapOf(
                "queueSize" to queue.size,
                "maxQueueSize" to MAX_QUEUE_SIZE,
                "droppedCount" to droppedCount.get()
            )
        }

        /**
         * Clears the queue and resets counters (useful for testing and recovery).
         */
        fun clearQueue() {
            queue.clear()
        }

        /**
         * Sanitizes and bounds input strings to prevent excessive RAM/DB footprint.
         */
        private fun sanitizeInput(input: String?, maxLength: Int): String {
            if (input == null) return ""
            val cleaned = input.replace("\u0000", "").trim()
            return if (cleaned.length > maxLength) cleaned.substring(0, maxLength) else cleaned
        }
    }

    private fun addSbnToQueue(sbn: StatusBarNotification) {
        try {
            val extras = sbn.notification.extras
            val rawTitle = extras?.getCharSequence("android.title")?.toString()
            val rawText = extras?.getCharSequence("android.text")?.toString()
            val isOngoing = sbn.isOngoing
            val rawPackageName = sbn.packageName

            // Sanitize & Validate inputs
            val packageName = sanitizeInput(rawPackageName ?: "unknown", maxLength = 256)
            val title = sanitizeInput(rawTitle, maxLength = 1000)
            val content = sanitizeInput(rawText, maxLength = 4000)

            if (packageName.isBlank() && title.isBlank() && content.isBlank()) {
                Log.w(TAG, "Skipping empty notification entry")
                return
            }

            // Ignore if same package, title, and content already exist in queue
            val isDuplicate = queue.any {
                it.packageName == packageName && it.title == title && it.content == content
            }
            if (isDuplicate) {
                return
            }

            // Enforce queue capacity bounds: evict oldest if queue reaches MAX_QUEUE_SIZE
            while (queue.size >= MAX_QUEUE_SIZE) {
                queue.poll()
                droppedCount.incrementAndGet()
            }

            val data = NotificationData(
                id = "notif_${idCounter.incrementAndGet()}",
                packageName = packageName,
                title = title,
                content = content,
                timestamp = sbn.postTime,
                category = sbn.notification.category,
                isOngoing = isOngoing
            )

            queue.add(data)
            // Structured diagnostic logging WITHOUT cleartext PII
            Log.d(TAG, "Captured: pkg=$packageName, title=${NotificationRedactor.redactTitle(title)}")
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
        val removedTitle = sbn.notification.extras?.getCharSequence("android.title")?.toString()
        Log.d(TAG, "Removed: pkg=${sbn.packageName}, title=${NotificationRedactor.redactTitle(removedTitle)}")
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
