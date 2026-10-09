package com.scope.attentions

import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are placed in a static [queue] which is drained
 * by [MainActivity] when Flutter requests them via MethodChannel, and pushed
 * directly over EventChannel if a listener is attached.
 *
 * Design decisions:
 *   - Uses a static ConcurrentLinkedQueue (thread-safe, lock-free) because
 *     the service runs in a separate context from MainActivity.
 *   - Emits events over EventChannel on the main looper thread.
 *   - Skips ongoing/persistent notifications by default (configurable).
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

        /** Static EventSink for emitting pushed notification events to Flutter. */
        @Volatile
        var eventSink: EventChannel.EventSink? = null

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
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue is empty.
         */
        fun drainQueue(now: Long = System.currentTimeMillis()): List<NotificationData> {
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
         * Clears the queue and resets internal state (for testing).
         */
        fun clearQueue() {
            queue.clear()
            idCounter = 0L
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int = queue.size

        /**
         * Safely emits a NotificationData event to the active EventSink on the main thread.
         */
        private fun emitEvent(data: NotificationData) {
            val sink = eventSink ?: return
            val looper = Looper.getMainLooper()
            if (looper != null) {
                Handler(looper).post {
                    try {
                        sink.success(data.toMap())
                    } catch (e: Exception) {
                        Log.e(TAG, "Error emitting notification event over EventChannel", e)
                    }
                }
            } else {
                try {
                    sink.success(data.toMap())
                } catch (e: Exception) {
                    Log.e(TAG, "Error emitting notification event over EventChannel", e)
                }
            }
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
            Log.d(TAG, "Captured: ${data.packageName} - ${NotificationRedactor.redactTitle(data.title)}")
            emitEvent(data)
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
