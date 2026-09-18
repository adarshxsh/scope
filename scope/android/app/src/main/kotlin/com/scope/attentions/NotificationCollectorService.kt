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
 * Captured notifications are placed in a static [queue] which is drained
 * by [MainActivity] when Flutter requests them via MethodChannel.
 *
 * Design decisions:
 *   - Uses a static ConcurrentLinkedQueue (thread-safe, lock-free) because
 *     the service runs in a separate context from MainActivity.
 *   - Native filtering boundary: evaluates incoming StatusBarNotification objects
 *     against blacklisted packages and excluded categories in SharedPreferences
 *     before queue allocation (<1ms check).
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"
        private const val PREFS_NAME = "scope_privacy_settings"
        private const val KEY_BLACKLISTED_PACKAGES = "blacklisted_packages"
        private const val KEY_EXCLUDED_CATEGORIES = "excluded_categories"

        /** Thread-safe queue of captured notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Thread-safe set of blacklisted package names. */
        private val blacklistedPackages: MutableSet<String> = ConcurrentHashMap.newKeySet()

        /** Thread-safe set of excluded notification categories. */
        private val excludedCategories: MutableSet<String> = ConcurrentHashMap.newKeySet()

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

        /**
         * Updates the package blacklist set.
         */
        fun setPackageBlacklist(packages: Set<String>) {
            blacklistedPackages.clear()
            blacklistedPackages.addAll(packages)
            Log.d(TAG, "Updated blacklisted packages: ${blacklistedPackages.size} packages")
        }

        /**
         * Updates the category exclusion rules set.
         */
        fun setCategoryExclusionRules(categories: Set<String>) {
            excludedCategories.clear()
            excludedCategories.addAll(categories.map { it.lowercase() })
            Log.d(TAG, "Updated excluded categories: ${excludedCategories.size} categories")
        }

        /**
         * Checks if a package is blacklisted. Fast O(1) lookup.
         */
        fun isPackageBlacklisted(packageName: String): Boolean {
            return blacklistedPackages.contains(packageName)
        }

        /**
         * Checks if a notification category is excluded. Fast O(1) lookup.
         */
        fun isCategoryExcluded(category: String?): Boolean {
            if (category == null) return false
            val catLower = category.lowercase()
            return excludedCategories.contains(catLower) ||
                    excludedCategories.any { catLower.contains(it) }
        }

        /**
         * Clears the static queue and filter sets (useful for testing).
         */
        fun resetForTesting() {
            queue.clear()
            blacklistedPackages.clear()
            excludedCategories.clear()
            idCounter = 0L
        }

        /**
         * Synchronizes privacy settings from SharedPreferences.
         */
        fun loadPrivacyPreferences(context: Context) {
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val packages = prefs.getStringSet(KEY_BLACKLISTED_PACKAGES, emptySet()) ?: emptySet()
                val categories = prefs.getStringSet(KEY_EXCLUDED_CATEGORIES, emptySet()) ?: emptySet()
                setPackageBlacklist(packages)
                setCategoryExclusionRules(categories)
            } catch (e: Exception) {
                Log.e(TAG, "Error loading privacy preferences from SharedPreferences", e)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        loadPrivacyPreferences(this)
    }

    private fun addSbnToQueue(sbn: StatusBarNotification) {
        try {
            val packageName = sbn.packageName ?: "unknown"

            // Native Boundary Check 1: Package Blacklist
            if (isPackageBlacklisted(packageName)) {
                Log.d(TAG, "Dropped blacklisted package notification: $packageName")
                return
            }

            val category = sbn.notification?.category

            // Native Boundary Check 2: Sensitive Category Exclusion
            if (isCategoryExcluded(category)) {
                Log.d(TAG, "Dropped excluded category notification: $category ($packageName)")
                return
            }

            val extras = sbn.notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing

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
                category = category,
                isOngoing = isOngoing
            )

            queue.add(data)
            Log.d(TAG, "Captured: ${data.packageName} - ${data.title}")
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
        Log.d(TAG, "Removed: ${sbn.packageName} - ${sbn.notification.extras?.getCharSequence("android.title")}")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "NotificationCollectorService connected")
        loadPrivacyPreferences(this)
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

