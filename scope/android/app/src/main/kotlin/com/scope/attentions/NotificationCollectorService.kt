package com.scope.attentions

import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are evaluated against pre-queue package exclusion rules
 * and sensitive system category rules before placing in a static [queue] drained
 * by [MainActivity] when Flutter requests them via MethodChannel.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"
        private const val PREFS_NAME = "scope_guardrails"
        private const val KEY_EXCLUDED_PACKAGES = "excluded_packages"
        private const val KEY_EXCLUDE_SYSTEM_CATEGORIES = "exclude_system_categories"
        private const val KEY_EXCLUDED_CATEGORIES = "excluded_categories"

        /** Maximum allowed queue size to prevent unbounded memory growth. */
        const val MAX_QUEUE_SIZE = 100

        /** Maximum time-to-live for queued notifications (15 minutes in milliseconds). */
        const val MAX_AGE_MS = 15 * 60 * 1000L

        /** Thread-safe queue of captured notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        private val excludedPackages: MutableSet<String> = ConcurrentHashMap.newKeySet()
        private val excludedCategories: MutableSet<String> = ConcurrentHashMap.newKeySet()
        @Volatile
        private var excludeSystemCategories: Boolean = false
        @Volatile
        private var isPrefsLoaded: Boolean = false

        private val SYSTEM_CATEGORIES = setOf(
            "transport",
            "media",
            "navigation",
            "progress",
            "service",
            "status",
            "sys",
            "system"
        )

        fun loadExclusions(context: Context) {
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val pkgs = prefs.getStringSet(KEY_EXCLUDED_PACKAGES, emptySet()) ?: emptySet()
                val cats = prefs.getStringSet(KEY_EXCLUDED_CATEGORIES, emptySet()) ?: emptySet()
                excludeSystemCategories = prefs.getBoolean(KEY_EXCLUDE_SYSTEM_CATEGORIES, false)

                excludedPackages.clear()
                excludedPackages.addAll(pkgs)

                excludedCategories.clear()
                excludedCategories.addAll(cats)

                isPrefsLoaded = true
            } catch (e: Exception) {
                Log.e(TAG, "Error loading exclusion preferences", e)
            }
        }

        fun setExcludedPackages(context: Context, packages: Set<String>) {
            excludedPackages.clear()
            excludedPackages.addAll(packages)
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().putStringSet(KEY_EXCLUDED_PACKAGES, packages).apply()
            } catch (e: Exception) {
                Log.e(TAG, "Error saving excluded packages", e)
            }
        }

        fun getExcludedPackages(context: Context): Set<String> {
            if (!isPrefsLoaded) {
                loadExclusions(context)
            }
            return excludedPackages.toSet()
        }

        fun setExcludeSystemCategories(context: Context, exclude: Boolean) {
            excludeSystemCategories = exclude
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().putBoolean(KEY_EXCLUDE_SYSTEM_CATEGORIES, exclude).apply()
            } catch (e: Exception) {
                Log.e(TAG, "Error saving exclude system categories", e)
            }
        }

        fun getExcludeSystemCategories(context: Context): Boolean {
            if (!isPrefsLoaded) {
                loadExclusions(context)
            }
            return excludeSystemCategories
        }

        fun setExcludedCategories(context: Context, categories: Set<String>) {
            excludedCategories.clear()
            excludedCategories.addAll(categories)
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().putStringSet(KEY_EXCLUDED_CATEGORIES, categories).apply()
            } catch (e: Exception) {
                Log.e(TAG, "Error saving excluded categories", e)
            }
        }

        fun getExcludedCategories(context: Context): Set<String> {
            if (!isPrefsLoaded) {
                loadExclusions(context)
            }
            return excludedCategories.toSet()
        }

        fun isExcluded(packageName: String, category: String?, isOngoing: Boolean): Boolean {
            if (excludedPackages.contains(packageName)) {
                return true
            }
            if (category != null && excludedCategories.contains(category)) {
                return true
            }
            if (excludeSystemCategories) {
                if (isOngoing) return true
                if (category != null && SYSTEM_CATEGORIES.contains(category.lowercase())) return true
            }
            return false
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
    }

    private fun addSbnToQueue(sbn: StatusBarNotification, now: Long = System.currentTimeMillis()) {
        try {
            if (!isPrefsLoaded) {
                loadExclusions(this)
            }

            val packageName = sbn.packageName ?: "unknown"
            val category = sbn.notification.category
            val isOngoing = sbn.isOngoing

            // Drop immediately if package or system category is excluded.
            // Executed in O(1) set lookup before logging PII or queueing.
            if (isExcluded(packageName, category, isOngoing)) {
                return
            }

            val extras = sbn.notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val timestamp = if (sbn.postTime > 0) sbn.postTime else now

            val data = NotificationData(
                id = "notif_${++idCounter}",
                packageName = packageName,
                title = title,
                content = text,
                timestamp = timestamp,
                category = category,
                isOngoing = isOngoing
            )

            addNotification(data, now)
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
        val packageName = sbn.packageName ?: "unknown"
        if (excludedPackages.contains(packageName)) {
            return
        }
        val removedTitle = sbn.notification.extras?.getCharSequence("android.title")?.toString()
        Log.d(TAG, "Removed: $packageName - ${NotificationRedactor.redactTitle(removedTitle)}")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        loadExclusions(this)
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
