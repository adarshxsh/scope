package com.scope.attentions

import java.security.MessageDigest

/**
 * Centralized log sanitization helper for redacting raw PII (notification titles,
 * body content, and sensitive tokens) into structural metadata before logging to
 * system Logcat buffers.
 */
object PiiLogSanitizer {

    enum class SanitizationMode {
        METADATA,
        MASKED,
        DIGEST
    }

    /**
     * Computes a truncated SHA-256 digest hex string for the given text.
     */
    fun sha256Digest(text: String?, length: Int = 8): String {
        if (text.isNullOrEmpty()) return "empty"
        return try {
            val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
            val hexString = StringBuilder()
            for (b in digest) {
                val hex = Integer.toHexString(0xff and b.toInt())
                if (hex.length == 1) hexString.append('0')
                hexString.append(hex)
            }
            if (length > 0 && length < hexString.length) {
                hexString.substring(0, length)
            } else {
                hexString.toString()
            }
        } catch (e: Exception) {
            "error"
        }
    }

    /**
     * Redacts string input into structural metadata according to the specified mode.
     */
    fun sanitize(
        text: String?,
        label: String? = null,
        mode: SanitizationMode = SanitizationMode.METADATA
    ): String {
        return try {
            if (text == null) {
                val lbl = if (!label.isNullOrEmpty()) "${label}_len" else "str_len"
                return when (mode) {
                    SanitizationMode.MASKED -> "[REDACTED]"
                    SanitizationMode.DIGEST -> "[sha256=null]"
                    SanitizationMode.METADATA -> "[$lbl=0, sha256=null]"
                }
            }

            val len = text.length
            when (mode) {
                SanitizationMode.MASKED -> "[REDACTED ($len chars)]"
                SanitizationMode.DIGEST -> "[sha256=${sha256Digest(text)}]"
                SanitizationMode.METADATA -> {
                    val lbl = if (!label.isNullOrEmpty()) "${label}_len" else "len"
                    "[$lbl=$len, sha256=${sha256Digest(text)}]"
                }
            }
        } catch (e: Exception) {
            "[REDACTED]"
        }
    }

    /**
     * Convenience method to mask string content with character count.
     */
    fun mask(text: String?): String {
        return sanitize(text, mode = SanitizationMode.MASKED)
    }

    /**
     * Convenience method to format string as structural metadata.
     */
    fun toMetadata(text: String?, label: String? = null): String {
        return sanitize(text, label = label, mode = SanitizationMode.METADATA)
    }

    /**
     * Convenience method to format captured notification details safely.
     */
    fun sanitizeNotification(packageName: String?, title: String?, content: String? = null): String {
        val pkg = packageName ?: "unknown"
        val titleMetadata = sanitize(title, label = "title")
        return if (content != null) {
            val contentMetadata = sanitize(content, label = "content")
            "$pkg - $titleMetadata - $contentMetadata"
        } else {
            "$pkg - $titleMetadata"
        }
    }

    /**
     * Sanitizes exception details to prevent leaking PII or raw message payloads.
     */
    fun sanitizeException(e: Throwable?): String {
        if (e == null) return "Exception(null)"
        return try {
            val className = e.javaClass.simpleName
            val message = e.message
            if (message.isNullOrEmpty()) {
                className
            } else {
                "$className(message=${mask(message)})"
            }
        } catch (ex: Exception) {
            "Exception(sanitization_failed)"
        }
    }
}
