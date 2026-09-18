package com.scope.attentions

import java.security.MessageDigest

/**
 * Utility for sanitizing sensitive PII text and hashing package names.
 */
object NotificationRedactor {

    private val OTP_REGEX = Regex("""\b(?:\d{4,8}|[A-Z0-9]{4,8})\b""", RegexOption.IGNORE_CASE)
    private val CARD_REGEX = Regex("""\b(?:\d[ -]*?){13,16}\b""")
    private val TOKEN_REGEX = Regex("""\b(?:bearer|token|auth)\s+[A-Za-z0-9._~+/-]+=*\b""", RegexOption.IGNORE_CASE)

    fun redact(text: String?): String {
        if (text.isNullOrEmpty()) return ""
        var result = text
        result = TOKEN_REGEX.replace(result, "[REDACTED_TOKEN]")
        result = CARD_REGEX.replace(result, "[REDACTED_CARD]")
        return result
    }

    fun redactOtp(text: String?): String {
        if (text.isNullOrEmpty()) return ""
        return OTP_REGEX.replace(text, "[REDACTED_OTP]")
    }

    fun hashPackageName(packageName: String?): String {
        if (packageName.isNullOrEmpty()) return "unknown_hash"
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            val hash = digest.digest(packageName.toByteArray(Charsets.UTF_8))
            hash.joinToString("") { "%02x".format(it) }.take(16)
        } catch (e: Exception) {
            "hash_error"
        }
    }
}
