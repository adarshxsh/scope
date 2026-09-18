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
 *   - Uses a static ConcurrentLinkedQueue (thread-safe, lock-free) because
 *     the service runs in a separate context from MainActivity.
 *   - Evaluates native ingestion guardrails at the OS listener boundary
 *     before queueing or sending payloads across MethodChannel IPC.
 *   - Skips ongoing/persistent notifications by default (configurable).
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"
        private const val PREFS_NAME = "scope_guardrails"

        /** Thread-safe queue of captured notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        // Native guardrails state initialized from SharedPreferences
        @Volatile var blockedPackages: Set<String> = emptySet()
        @Volatile var allowedPackages: Set<String> = emptySet()
        @Volatile var isWhitelistMode: Boolean = false
        @Volatile var excludeOtp: Boolean = true
        @Volatile var excludeFinance: Boolean = true
        @Volatile var excludeHealth: Boolean = false
        @Volatile var excludeSystemServices: Boolean = true
        @Volatile var droppedCount: Int = 0

        @Volatile private var isGuardrailsInitialized: Boolean = false

        private val OTP_REGEX = Regex("(?i)\\b(otp|2fa|verification code|passcode|one-time password|auth code|security code|login code)\\b|\\b\\d{4,8}\\b.*(?:code|verify|verification|otp|pin)")
        private val FINANCE_KEYWORDS_REGEX = Regex("(?i)\\b(bank|debit|credit|account debited|account credited|upi|transaction|withdrawal|deposit|atm|card ending|balance|payment|invoice|bill due|spend|spent|transfer)\\b")
        private val HEALTH_KEYWORDS_REGEX = Regex("(?i)\\b(doctor|medical|appointment|hospital|prescription|patient|clinic|pharmacy|health|diagnostic|vaccination|lab report)\\b")

        fun ensureGuardrailsInitialized(context: Context) {
            if (!isGuardrailsInitialized) {
                synchronized(this) {
                    if (!isGuardrailsInitialized) {
                        loadGuardrails(context)
                    }
                }
            }
        }

        fun loadGuardrails(context: Context) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            blockedPackages = prefs.getStringSet("blocked_packages", emptySet()) ?: emptySet()
            allowedPackages = prefs.getStringSet("allowed_packages", emptySet()) ?: emptySet()
            isWhitelistMode = prefs.getBoolean("is_whitelist_mode", false)
            excludeOtp = prefs.getBoolean("exclude_otp", true)
            excludeFinance = prefs.getBoolean("exclude_finance", true)
            excludeHealth = prefs.getBoolean("exclude_health", false)
            excludeSystemServices = prefs.getBoolean("exclude_system_services", true)
            droppedCount = prefs.getInt("dropped_count", 0)
            isGuardrailsInitialized = true
        }

        fun updateGuardrails(
            context: Context,
            blocked: List<String>?,
            allowed: List<String>?,
            whitelistMode: Boolean?,
            otp: Boolean?,
            finance: Boolean?,
            health: Boolean?,
            systemServices: Boolean?
        ): Map<String, Any> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val editor = prefs.edit()

            if (blocked != null) {
                blockedPackages = blocked.toSet()
                editor.putStringSet("blocked_packages", blockedPackages)
            }
            if (allowed != null) {
                allowedPackages = allowed.toSet()
                editor.putStringSet("allowed_packages", allowedPackages)
            }
            if (whitelistMode != null) {
                isWhitelistMode = whitelistMode
                editor.putBoolean("is_whitelist_mode", isWhitelistMode)
            }
            if (otp != null) {
                excludeOtp = otp
                editor.putBoolean("exclude_otp", excludeOtp)
            }
            if (finance != null) {
                excludeFinance = finance
                editor.putBoolean("exclude_finance", excludeFinance)
            }
            if (health != null) {
                excludeHealth = health
                editor.putBoolean("exclude_health", excludeHealth)
            }
            if (systemServices != null) {
                excludeSystemServices = systemServices
                editor.putBoolean("exclude_system_services", excludeSystemServices)
            }
            editor.apply()
            isGuardrailsInitialized = true

            return getGuardrailsMap()
        }

        fun getGuardrailsMap(): Map<String, Any> {
            return mapOf(
                "blockedPackages" to blockedPackages.toList(),
                "allowedPackages" to allowedPackages.toList(),
                "isWhitelistMode" to isWhitelistMode,
                "excludeOtp" to excludeOtp,
                "excludeFinance" to excludeFinance,
                "excludeHealth" to excludeHealth,
                "excludeSystemServices" to excludeSystemServices,
                "droppedCount" to droppedCount
            )
        }

        fun matchesPattern(packageName: String, pattern: String): Boolean {
            if (pattern == packageName) return true
            if (!pattern.contains("*") && !pattern.contains("?")) return false
            return try {
                val regexPattern = "^" + Regex.escape(pattern).replace("\\*", ".*").replace("\\?", ".") + "$"
                Regex(regexPattern, RegexOption.IGNORE_CASE).matches(packageName)
            } catch (e: Exception) {
                false
            }
        }

        fun shouldDropNotification(sbn: StatusBarNotification): Boolean {
            val pkg = sbn.packageName ?: "unknown"

            // 1. Package Blacklisting
            if (blockedPackages.isNotEmpty()) {
                if (blockedPackages.any { pattern -> matchesPattern(pkg, pattern) }) {
                    return true
                }
            }

            // 2. Package Whitelisting Mode
            if (isWhitelistMode) {
                val isAllowed = allowedPackages.any { pattern -> matchesPattern(pkg, pattern) }
                if (!isAllowed) {
                    return true
                }
            }

            val category = sbn.notification?.category ?: ""
            val extras = sbn.notification?.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val fullText = "$title $text"

            // 3. Sensitive Category: System Services & Ongoing
            if (excludeSystemServices) {
                if (sbn.isOngoing) {
                    return true
                }
                val sysCategories = setOf("sys", "system", "service", "progress", "transport", "navigation", "status")
                if (sysCategories.contains(category.lowercase())) {
                    return true
                }
                if (pkg.startsWith("android") || pkg == "com.android.systemui" || pkg == "com.google.android.gms") {
                    return true
                }
            }

            // 4. Sensitive Category: OTP / 2FA
            if (excludeOtp) {
                if (category.equals("otp", ignoreCase = true) || category.equals("2fa", ignoreCase = true)) {
                    return true
                }
                if (OTP_REGEX.containsMatchIn(fullText)) {
                    return true
                }
            }

            // 5. Sensitive Category: Finance / Banking
            if (excludeFinance) {
                if (category.equals("finance", ignoreCase = true) || category.equals("banking", ignoreCase = true)) {
                    return true
                }
                val isFinanceApp = pkg.contains("bank", ignoreCase = true) ||
                        pkg.contains("paytm", ignoreCase = true) ||
                        pkg.contains("phonepe", ignoreCase = true) ||
                        pkg.contains("gpay", ignoreCase = true) ||
                        pkg.contains("finance", ignoreCase = true) ||
                        pkg.contains("wallet", ignoreCase = true)
                if (isFinanceApp || FINANCE_KEYWORDS_REGEX.containsMatchIn(fullText)) {
                    return true
                }
            }

            // 6. Sensitive Category: Health
            if (excludeHealth) {
                if (category.equals("health", ignoreCase = true) || category.equals("medical", ignoreCase = true) || category.equals("workout", ignoreCase = true)) {
                    return true
                }
                if (HEALTH_KEYWORDS_REGEX.containsMatchIn(fullText)) {
                    return true
                }
            }

            return false
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
            ensureGuardrailsInitialized(this)
            if (shouldDropNotification(sbn)) {
                droppedCount++
                val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().putInt("dropped_count", droppedCount).apply()
                Log.d(TAG, "Notification dropped by ingestion guardrails. Total dropped: $droppedCount")
                return
            }

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
        Log.d(TAG, "Removed: ${sbn.packageName}")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "NotificationCollectorService connected")
        try {
            ensureGuardrailsInitialized(this)
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

