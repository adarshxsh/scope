package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicInteger

/**
 * Android service that captures incoming notifications with strict ingestion guardrails.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are evaluated against pre-ingestion guardrails before
 * being placed in [queue] for draining by [MainActivity].
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Thread-safe queue of captured notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        // Ingestion Guardrail Settings
        @Volatile
        var blacklistedPackages: Set<String> = emptySet()

        @Volatile
        var whitelistedPackages: Set<String> = emptySet()

        @Volatile
        var isWhitelistModeEnabled: Boolean = false

        @Volatile
        var excludedCategories: Set<String> = emptySet()

        @Volatile
        var maxTitleLength: Int = 1000

        @Volatile
        var maxContentLength: Int = 5000

        // Telemetry Metrics
        val totalEvaluated = AtomicInteger(0)
        val totalIngested = AtomicInteger(0)
        val totalExcludedBlacklist = AtomicInteger(0)
        val totalExcludedWhitelist = AtomicInteger(0)
        val totalExcludedSensitiveCategory = AtomicInteger(0)
        val totalRejectedValidation = AtomicInteger(0)
        val totalErrors = AtomicInteger(0)

        /**
         * Updates guardrail configuration from Flutter.
         */
        fun updateGuardrails(configMap: Map<String, Any?>?) {
            if (configMap == null) return

            try {
                val blacklist = (configMap["blacklistedPackages"] as? List<*>)
                    ?.mapNotNull { it?.toString()?.lowercase()?.trim() }
                    ?.filter { it.isNotEmpty() }
                    ?.toSet() ?: emptySet()

                val whitelist = (configMap["whitelistedPackages"] as? List<*>)
                    ?.mapNotNull { it?.toString()?.lowercase()?.trim() }
                    ?.filter { it.isNotEmpty() }
                    ?.toSet() ?: emptySet()

                val isWhitelistMode = configMap["isWhitelistModeEnabled"] as? Boolean ?: false

                val categories = (configMap["excludedCategories"] as? List<*>)
                    ?.mapNotNull { it?.toString()?.lowercase()?.trim() }
                    ?.filter { it.isNotEmpty() }
                    ?.toSet() ?: emptySet()

                blacklistedPackages = blacklist
                whitelistedPackages = whitelist
                isWhitelistModeEnabled = isWhitelistMode
                excludedCategories = categories
                maxTitleLength = configMap["maxTitleLength"] as? Int ?: 1000
                maxContentLength = configMap["maxContentLength"] as? Int ?: 5000

                Log.d(TAG, "[Guardrails Updated] Blacklist size: ${blacklistedPackages.size}, Whitelist size: ${whitelistedPackages.size}, Mode: $isWhitelistModeEnabled, Excluded categories: $excludedCategories")
            } catch (e: Exception) {
                Log.e(TAG, "Error updating guardrails config", e)
            }
        }

        /**
         * Returns current ingestion telemetry metrics.
         */
        fun getTelemetryMap(): Map<String, Int> {
            return mapOf(
                "totalEvaluated" to totalEvaluated.get(),
                "totalIngested" to totalIngested.get(),
                "totalExcludedBlacklist" to totalExcludedBlacklist.get(),
                "totalExcludedWhitelist" to totalExcludedWhitelist.get(),
                "totalExcludedSensitiveCategory" to totalExcludedSensitiveCategory.get(),
                "totalRejectedValidation" to totalRejectedValidation.get(),
                "totalErrors" to totalErrors.get()
            )
        }

        /**
         * Drains all notifications from the queue and returns them.
         */
        fun drainQueue(): List<NotificationData> {
            val result = mutableListOf<NotificationData>()
            while (true) {
                val item = queue.poll() ?: break
                result.add(item)
            }
            return result
        }

        /** Returns the current queue size (for diagnostics). */
        fun queueSize(): Int = queue.size

        /**
         * Evaluates guardrails on a notification before queuing.
         * Returns true if allowed, false if excluded.
         */
        private fun evaluateGuardrails(
            pkg: String,
            title: String,
            content: String,
            category: String?,
            postTime: Long
        ): Boolean {
            totalEvaluated.incrementAndGet()

            try {
                val lowerPkg = pkg.lowercase().trim()

                // 1. Validation Guardrails
                if (lowerPkg.isEmpty()) {
                    totalRejectedValidation.incrementAndGet()
                    Log.d(TAG, "[Guardrail Rejected] Empty package name")
                    return false
                }

                if (postTime <= 0) {
                    totalRejectedValidation.incrementAndGet()
                    Log.d(TAG, "[Guardrail Rejected] pkg: $lowerPkg | Invalid timestamp: $postTime")
                    return false
                }

                // 2. Blacklist Guardrails
                if (blacklistedPackages.contains(lowerPkg)) {
                    totalExcludedBlacklist.incrementAndGet()
                    Log.d(TAG, "[Guardrail Excluded] pkg: $lowerPkg | Reason: Package blacklisted")
                    return false
                }

                // 3. Whitelist Guardrails
                if (isWhitelistModeEnabled && !whitelistedPackages.contains(lowerPkg)) {
                    totalExcludedWhitelist.incrementAndGet()
                    Log.d(TAG, "[Guardrail Excluded] pkg: $lowerPkg | Reason: Package not in whitelist")
                    return false
                }

                // 4. Sensitive Category Exclusions
                val detectedCategory = detectSensitiveCategory(lowerPkg, title, content, category)
                if (detectedCategory != null && excludedCategories.contains(detectedCategory)) {
                    totalExcludedSensitiveCategory.incrementAndGet()
                    Log.d(TAG, "[Guardrail Excluded] pkg: $lowerPkg | Reason: Sensitive category '$detectedCategory' excluded")
                    return false
                }

                totalIngested.incrementAndGet()
                return true
            } catch (e: Exception) {
                totalErrors.incrementAndGet()
                Log.e(TAG, "[Guardrail Error] pkg: $pkg | Exception evaluating guardrails", e)
                return false
            }
        }

        private fun detectSensitiveCategory(
            pkg: String,
            title: String,
            content: String,
            category: String?
        ): String? {
            val combined = "${title.lowercase()} ${content.lowercase()}"
            val rawCat = category?.lowercase()?.trim() ?: ""

            // Banking & Finance
            val isFinancePkg = pkg.contains("bank") || pkg.contains("paytm") || pkg.contains("phonepe") ||
                    pkg.contains("groww") || pkg.contains("zerodha") || pkg.contains("cred") || pkg.contains("gpay")
            val isFinanceCat = rawCat == "finance" || rawCat == "upi"
            val isFinanceKeywords = combined.contains("debited") || combined.contains("credited") ||
                    combined.contains("account balance") || combined.contains("upi collect") ||
                    combined.contains("transaction alert") || combined.contains("bank transfer")

            if (isFinancePkg || isFinanceCat || isFinanceKeywords) {
                return "banking_finance"
            }

            // OTP & Security
            val isOtpCat = rawCat == "otp" || rawCat == "security"
            val isOtpKeywords = combined.contains("otp") || combined.contains("verification code") ||
                    combined.contains("security code") || combined.contains("one time password") ||
                    (combined.contains("code") && combined.contains("verify"))

            if (isOtpCat || isOtpKeywords) {
                return "otp_security"
            }

            // Health & Medical
            val isHealthPkg = pkg.contains("health") || pkg.contains("patient") || pkg.contains("hospital") ||
                    pkg.contains("doctor") || pkg.contains("apollo") || pkg.contains("pharmacy")
            val isHealthKeywords = combined.contains("prescription") || combined.contains("doctor appointment") ||
                    combined.contains("medical report") || combined.contains("lab test")

            if (isHealthPkg || isHealthKeywords) {
                return "health_medical"
            }

            // Personal Messaging
            val isMsgPkg = pkg == "com.whatsapp" || pkg == "com.slack" || pkg == "org.telegram.messenger" ||
                    pkg == "com.facebook.orca" || pkg == "com.google.android.talk" || pkg == "com.discord"
            val isMsgCat = rawCat == "msg" || rawCat == "conversation"

            if (isMsgPkg || isMsgCat) {
                return "personal_messaging"
            }

            return null
        }
    }

    private fun addSbnToQueue(sbn: StatusBarNotification) {
        try {
            val extras = sbn.notification.extras
            var title = extras?.getCharSequence("android.title")?.toString() ?: ""
            var text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: ""
            val category = sbn.notification.category
            val postTime = sbn.postTime

            // Truncate payloads if exceeding max lengths
            if (title.length > maxTitleLength) {
                title = title.substring(0, maxTitleLength)
            }
            if (text.length > maxContentLength) {
                text = text.substring(0, maxContentLength)
            }

            // Evaluate pre-ingestion guardrails
            if (!evaluateGuardrails(packageName, title, text, category, postTime)) {
                return
            }

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
                timestamp = postTime,
                category = category,
                isOngoing = isOngoing
            )

            queue.add(data)
            Log.d(TAG, "Captured notification from package: ${data.packageName}")
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
        Log.d(TAG, "Removed notification from package: ${sbn.packageName}")
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

