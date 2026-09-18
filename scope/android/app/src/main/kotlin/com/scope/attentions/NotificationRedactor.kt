package com.scope.attentions

/**
 * Utility object for redacting sensitive PII from notification titles and content
 * prior to writing to Android system Logcat buffers.
 */
object NotificationRedactor {
    private val TOKEN_REGEX = Regex(
        """\b(Bearer\s+[A-Za-z0-9._~+/-]+=*|[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,})\b""",
        RegexOption.IGNORE_CASE
    )

    private val URL_REGEX = Regex(
        """https?://[^\s]+""",
        RegexOption.IGNORE_CASE
    )

    private val EMAIL_REGEX = Regex(
        """\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b""",
        RegexOption.IGNORE_CASE
    )

    private val PHONE_REGEX = Regex(
        """(?:\+\d{1,3}[\s-]?)?\(?\d{3}\)?[\s-]?\d{3}[\s-]?\d{4}\b"""
    )

    private val MONEY_REGEX = Regex(
        """(?:\$|₹|€|£|USD|INR|EUR|GBP)\s?\d+(?:,\d{3})*(?:\.\d{1,2})?""",
        RegexOption.IGNORE_CASE
    )

    private val OTP_REGEX = Regex(
        """\b\d{4,8}\b"""
    )

    /**
     * Sanitizes sensitive information from [text] for safe logging in Logcat.
     */
    fun redact(text: String?): String {
        if (text.isNullOrEmpty()) return ""

        var sanitized = text
        sanitized = TOKEN_REGEX.replace(sanitized, "[REDACTED_TOKEN]")
        sanitized = URL_REGEX.replace(sanitized, "[REDACTED_URL]")
        sanitized = EMAIL_REGEX.replace(sanitized, "[REDACTED_EMAIL]")
        sanitized = PHONE_REGEX.replace(sanitized, "[REDACTED_PHONE]")
        sanitized = MONEY_REGEX.replace(sanitized, "[REDACTED_MONEY]")
        sanitized = OTP_REGEX.replace(sanitized, "[REDACTED_OTP]")

        return sanitized
    }
}
