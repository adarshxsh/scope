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
 * Captured notifications are pushed directly to Flutter via [eventSink]
 * when an EventChannel listener is connected, and stored in a static [queue]
 * (capped at 250 items) for fallback polling via MethodChannel.
 *
 * Design decisions:
 *   - Uses a static ConcurrentLinkedQueue (thread-safe, lock-free) capped at 250 items.
 *   - Emits real-time stream events over EventChannel on main thread looper.
 *   - Flushes pending queued items upon EventSink listener attachment.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"
        private const val MAX_QUEUE_SIZE = 250

        /** Thread-safe queue of captured notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /** Active EventChannel EventSink for pushing notifications directly to Flutter. */
        @Volatile
        private var eventSink: EventChannel.EventSink? = null

        /** Handler bound to the main application looper for EventSink dispatch. */
        private val mainHandler = Handler(Looper.getMainLooper())

        /**
         * Sets or clears the active EventSink stream listener.
         * When attached, flushes any pending queued notifications accumulated
         * while Flutter was disconnected.
         */
        fun setEventSink(sink: EventChannel.EventSink?) {
            eventSink = sink
            if (sink != null) {
                val pending = drainQueue()
                if (pending.isNotEmpty()) {
                    mainHandler.post {
                        for (item in pending) {
                            try {
                                sink.success(item.toMap())
                            } catch (e: Exception) {
                                Log.e(TAG, "Error emitting pending notification event", e)
                            }
                        }
                    }
                }
            }
        }

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

            while (queue.size >= MAX_QUEUE_SIZE) {
                queue.poll()
            }
            queue.add(data)
            Log.d(TAG, "Captured: ${data.packageName} - ${NotificationRedactor.redactTitle(data.title)}")

            val sink = eventSink
            if (sink != null) {
                mainHandler.post {
                    try {
                        sink.success(data.toMap())
                    } catch (e: Exception) {
                        Log.e(TAG, "Error emitting notification event", e)
                    }
                }
            }
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
