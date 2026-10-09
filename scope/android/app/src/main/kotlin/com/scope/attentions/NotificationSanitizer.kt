package com.scope.attentions

import android.util.Log
import java.security.MessageDigest

/**
 * Utility for sanitizing log output to protect user PII in system logs
 * and restricting debug logs to debug builds.
 */
object NotificationSanitizer {

    /**
     * Computes an 8-character truncated SHA-256 hash of the notification title.
     * Returns an empty string if the input is null or empty.
     *
     * @param title The cleartext notification title.
     * @return 8-character hex hash or empty string.
     */
    fun hashTitle(title: String?): String {
        if (title.isNullOrEmpty()) return ""
        val digest = MessageDigest.getInstance("SHA-256")
        val hashBytes = digest.digest(title.toByteArray(Charsets.UTF_8))
        return hashBytes.joinToString("") { "%02x".format(it) }.take(8)
    }

    /**
     * Emits a Log.d debug log message only when [isDebug] is true (debug builds).
     * The message supplier lambda is lazily evaluated only when [isDebug] is true.
     *
     * @param tag The log tag.
     * @param messageSupplier Lambda returning the log message.
     * @param isDebug Flag indicating if debug logging is enabled (defaults to [BuildConfig.DEBUG]).
     */
    inline fun logDebug(
        tag: String,
        messageSupplier: () -> String,
        isDebug: Boolean = BuildConfig.DEBUG
    ) {
        if (isDebug) {
            try {
                Log.d(tag, messageSupplier())
            } catch (e: Throwable) {
                // In unmocked JVM test environments, android.util.Log.d throws RuntimeException
            }
        }
    }
}
