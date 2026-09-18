package com.scope.attentions

/**
 * In-process pattern redactor that sanitizes notification title and text
 * fields before they are enqueued into memory.
 *
 * Targets sensitive PII patterns including:
 *   - Email addresses
 *   - Credit card numbers
 *   - Monetary balances and transaction amounts
 *   - OTPs (4-8 digit standalone passcodes)
 */
object NotificationRedactor {

    private val EMAIL_REGEX = Regex("(?i)\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b")
    private val CREDIT_CARD_REGEX = Regex("(?i)\\b\\d{4}[- ]?\\d{4}[- ]?\\d{4}[- ]?\\d{1,4}\\b|\\b\\d{13,19}\\b")
    private val MONETARY_REGEX = Regex("(?i)(?:[\\$€£₹]|Rs\\.?|USD|EUR|INR|GBP|AUD|CAD)\\s?\\d+(?:,\\d{3})*(?:\\.\\d{1,2})?|\\b\\d+(?:,\\d{3})*(?:\\.\\d{1,2})?\\s?(?:USD|EUR|INR|GBP|AUD|CAD)\\b")
    private val OTP_REGEX = Regex("\\b\\d{4,8}\\b")

    /**
     * Redacts sensitive PII and OTP substrings in [text].
     * Replaces matched OTPs with [REDACTED_OTP] and emails, card numbers,
     * and monetary balances with [REDACTED_PII].
     */
    @JvmStatic
    fun redact(text: String?): String {
        if (text.isNullOrEmpty()) {
            return ""
        }
        var sanitized = text
        sanitized = EMAIL_REGEX.replace(sanitized, "[REDACTED_PII]")
        sanitized = CREDIT_CARD_REGEX.replace(sanitized, "[REDACTED_PII]")
        sanitized = MONETARY_REGEX.replace(sanitized, "[REDACTED_PII]")
        sanitized = OTP_REGEX.replace(sanitized, "[REDACTED_OTP]")
        return sanitized
    }
}
