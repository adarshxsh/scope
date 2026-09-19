package com.scope.attentions

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
 *   - Uses a static ConcurrentLinkedQueue (thread-safe, lock-free) bounded to [MAX_QUEUE_SIZE].
 *   - Applies pre-ingestion filtering for ongoing events, package blacklists, and excluded categories.
 *   - Sanitizes logcat output using SHA-256 package hashes and PII redaction.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"
        private const val MAX_QUEUE_SIZE = 250
        private const val PREFS_NAME = "scope_guardrails"

        /** Thread-safe queue of captured notifications bounded to [MAX_QUEUE_SIZE]. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        private val DEFAULT_BLACKLISTED = setOf("com.android.systemui", "android")
        private val DEFAULT_EXCLUDED_CATEGORIES = setOf("progress", "navigation", "service", "sys", "system", "transport", "status")

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

    private fun getBlacklistedPackages(): Set<String> {
        return try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.getStringSet("blacklistedPackages", DEFAULT_BLACKLISTED) ?: DEFAULT_BLACKLISTED
        } catch (e: Exception) {
            DEFAULT_BLACKLISTED
        }
    }

    private fun getExcludedCategories(): Set<String> {
        return try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.getStringSet("excludedCategories", DEFAULT_EXCLUDED_CATEGORIES) ?: DEFAULT_EXCLUDED_CATEGORIES
        } catch (e: Exception) {
            DEFAULT_EXCLUDED_CATEGORIES
        }
    }

    private fun addSbnToQueue(sbn: StatusBarNotification) {
        try {
            val isOngoing = sbn.isOngoing || (sbn.notification.flags and android.app.Notification.FLAG_ONGOING_EVENT) != 0
            if (isOngoing) return

            val packageName = sbn.packageName ?: "unknown"
            val blacklisted = getBlacklistedPackages()
            if (blacklisted.contains(packageName)) return

            val category = sbn.notification.category?.lowercase() ?: ""
            val excludedCat = getExcludedCategories().map { it.lowercase() }.toSet()
            if (category.isNotEmpty() && excludedCat.contains(category)) return

            val extras = sbn.notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""

            // Ignore if same package, title, and content already exist in queue
            val isDuplicate = queue.any {
                it.packageName == packageName && it.title == title && it.content == text
            }
            if (isDuplicate) return

            // Bounded queue eviction: drop oldest if max size reached
            while (queue.size >= MAX_QUEUE_SIZE) {
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
            val pkgHash = NotificationRedactor.hashPackageName(packageName)
            val cleanTitle = NotificationRedactor.redactTitle(data.title)
            Log.d(TAG, "Captured: $pkgHash - $cleanTitle")
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
        val pkgHash = NotificationRedactor.hashPackageName(sbn.packageName)
        val removedTitle = sbn.notification.extras?.getCharSequence("android.title")?.toString()
        val cleanTitle = NotificationRedactor.redactTitle(removedTitle)
        Log.d(TAG, "Removed: $pkgHash - $cleanTitle")
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
