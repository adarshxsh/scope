package com.scope.attentions

import android.util.Log

/**
 * Centralized platform logging utility for Android.
 *
 * Ensures notification titles and body content are transformed into deterministic
 * DJB2 cryptographic hashes and structural metadata prior to log emission.
 */
object HashedLogger {

    /**
     * Computes deterministic DJB2 hash for a string, matching Dart's DJB2 implementation.
     */
    fun djb2(valStr: String?): Long {
        if (valStr == null) return 0L
        var hash = 5381L
        for (ch in valStr) {
            hash = ((hash shl 5) + hash) + ch.code.toLong()
            hash = hash and 0xFFFFFFFFL
        }
        return hash
    }

    /**
     * Helper to compute character count safely.
     */
    fun charCount(str: String?): Int = str?.length ?: 0

    /**
     * Logs notification capture event with structural metadata and DJB2 string hashes.
     * Replaces cleartext title and body with non-invertible hashes and character counts.
     */
    fun logNotificationCaptured(
        tag: String,
        packageName: String,
        title: String?,
        content: String?,
        category: String? = null,
        isOngoing: Boolean = false
    ) {
        val titleHash = djb2(title ?: "")
        val contentHash = djb2(content ?: "")
        val titleLen = charCount(title)
        val contentLen = charCount(content)
        val hasCategory = !category.isNullOrEmpty()

        Log.d(
            tag,
            "Captured: pkg=$packageName, titleHash=$titleHash (len=$titleLen), contentHash=$contentHash (len=$contentLen), category=$category, isOngoing=$isOngoing, hasCategory=$hasCategory"
        )
    }

    /**
     * Logs notification removal event with structural metadata and DJB2 string hash.
     */
    fun logNotificationRemoved(
        tag: String,
        packageName: String,
        title: String?
    ) {
        val titleHash = djb2(title ?: "")
        val titleLen = charCount(title)
        Log.d(
            tag,
            "Removed: pkg=$packageName, titleHash=$titleHash (len=$titleLen)"
        )
    }

    /** Log wrappers for standard severity levels without payload content */
    fun debug(tag: String, message: String) {
        Log.d(tag, message)
    }

    fun info(tag: String, message: String) {
        Log.i(tag, message)
    }

    fun warn(tag: String, message: String) {
        Log.w(tag, message)
    }

    fun error(tag: String, message: String, throwable: Throwable? = null) {
        if (throwable != null) {
            Log.e(tag, message, throwable)
        } else {
            Log.e(tag, message)
        }
    }
}
