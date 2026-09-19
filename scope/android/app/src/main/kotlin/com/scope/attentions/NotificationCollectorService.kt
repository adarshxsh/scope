package com.scope.attentions

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.concurrent.ConcurrentLinkedQueue

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
 *   - Uses a static ConcurrentLinkedQueue (thread-safe, lock-free) because
 *     the service runs in a separate context from MainActivity.
 *   - Applies Layer 1 OS-level guardrails: drops ongoing events, system noise
 *     categories, and blacklisted packages before queuing.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Thread-safe queue of captured notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

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
            val notification = sbn.notification ?: return
            val isOngoing = sbn.isOngoing || (notification.flags and Notification.FLAG_ONGOING_EVENT) != 0

            val prefs = getSharedPreferences("scope_guardrails", Context.MODE_PRIVATE)
            val blockOngoing = prefs.getBoolean("block_ongoing", true)

            // Drop ongoing notifications at Layer 1
            if (blockOngoing && isOngoing) {
                Log.d(TAG, "Dropped ongoing notification at OS level: ${sbn.packageName}")
                return
            }

            // Drop system noise categories at Layer 1
            val category = notification.category ?: ""
            val categoryLower = category.lowercase()
            val noiseCategories = setOf(
                "progress", "navigation", "service", "sys", "system", "transport", "status"
            )
            if (noiseCategories.contains(categoryLower)) {
                Log.d(TAG, "Dropped system noise category at OS level: $category for ${sbn.packageName}")
                return
            }

            // Drop user-blacklisted packages at Layer 1
            val packageName = sbn.packageName ?: "unknown"
            val blockedPackages = prefs.getStringSet("blocked_packages", emptySet()) ?: emptySet()
            if (blockedPackages.map { it.lowercase() }.contains(packageName.lowercase())) {
                Log.d(TAG, "Dropped blacklisted package at OS level: $packageName")
                return
            }

            // Drop excluded categories at Layer 1
            val excludedCategories = prefs.getStringSet("excluded_categories", emptySet()) ?: emptySet()
            if (excludedCategories.map { it.lowercase() }.contains(categoryLower)) {
                Log.d(TAG, "Dropped excluded category at OS level: $category for $packageName")
                return
            }

            val extras = notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""

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
                category = notification.category,
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
