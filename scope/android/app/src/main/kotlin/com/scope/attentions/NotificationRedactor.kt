package com.scope.attentions

import java.util.regex.Pattern

/**
 * Utility for sanitizing notification titles, text, and metadata
 * to prevent plain text PII exposure in system logcat logs.
 */
object NotificationRedactor {

    private val OTP_PATTERN = Pattern.compile("\\b\\d{4,8}\\b")
    private val TOKEN_PATTERN = Pattern.compile("(?i)\\b(token|auth|session|key)\\s*[:=]\\s*[A-Za-z0-9._\\-]+|(?i)\\b(bearer)\\s*[:=]?\\s*[A-Za-z0-9._\\-]+\\b(?![=:])")
    private val EMAIL_PATTERN = Pattern.compile("[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}")

    /**
     * Redacts PII (passcodes, OTPs, auth tokens, emails) from text before logging.
     */
    fun redact(text: String?): String {
        if (text.isNullOrEmpty()) return ""

        var sanitized: String = text
        val matcher = TOKEN_PATTERN.matcher(sanitized)
        val sb = StringBuffer()
        while (matcher.find()) {
            val key = matcher.group(1) ?: matcher.group(2) ?: "token"
            matcher.appendReplacement(sb, "$key=[REDACTED_TOKEN]")
        }
        matcher.appendTail(sb)
        sanitized = sb.toString()

        sanitized = EMAIL_PATTERN.matcher(sanitized).replaceAll("[REDACTED_EMAIL]")
        sanitized = OTP_PATTERN.matcher(sanitized).replaceAll("[REDACTED_OTP]")

        return sanitized
    }
}
