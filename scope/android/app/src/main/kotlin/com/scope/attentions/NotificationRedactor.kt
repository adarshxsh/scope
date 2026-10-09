package com.scope.attentions

import android.util.Log

/**
 * Regex-based redaction engine that automatically detects and masks sensitive patterns
 * such as OTPs/passcodes, credit card numbers, secret tokens, emails, URLs, monetary amounts, and phone numbers.
 */
object NotificationRedactor {

    // Regex patterns matching sensitive data
    private val cardRegex = Regex("""\b(?:\d[ -]*?){13,19}\b""")
    private val emailRegex = Regex("""\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b""")
    private val urlRegex = Regex("""https?://[^\s]+|www\.[^\s]+""", RegexOption.IGNORE_CASE)
    private val monetaryRegex = Regex("""(?:[\$₹€£]|USD|INR|EUR|GBP|Rs\.?)\s*[\d,]+(?:\.\d{1,2})?|\b[\d,]+(?:\.\d{1,2})?\s*(?:USD|INR|EUR|GBP|dollars|rupees|Rs\.?)""", RegexOption.IGNORE_CASE)
    private val tokenKvRegex = Regex("""(?i)\b(token|secret|bearer|api[_-]?key|auth[_-]?code|password)\s*[:=]\s*([a-zA-Z0-9_-]{8,})""")
    private val tokenRegex = Regex("""\b[A-Fa-f0-9]{32,64}\b|\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b""")
    private val phoneRegex = Regex("""\b(?:\+\d{1,3}[- ]?)?\(?\d{3}\)?[- ]?\d{3}[- ]?\d{4}\b""")
    private val otpRegex = Regex("""\b\d{4,8}\b""")

    /**
     * Redacts sensitive PII from the input string safely.
     * Returns an empty string if [text] is null or empty.
     */
    @JvmStatic
    fun redact(text: String?): String {
        if (text.isNullOrEmpty()) {
            return ""
        }

        return try {
            var result = text
            result = cardRegex.replace(result, "[REDACTED_CARD]")
            result = emailRegex.replace(result, "[REDACTED_EMAIL]")
            result = urlRegex.replace(result, "[REDACTED_URL]")
            result = monetaryRegex.replace(result, "[REDACTED_AMOUNT]")
            result = tokenKvRegex.replace(result, "$1: [REDACTED_TOKEN]")
            result = tokenRegex.replace(result, "[REDACTED_TOKEN]")
            result = phoneRegex.replace(result, "[REDACTED_PHONE]")
            result = otpRegex.replace(result, "[REDACTED_OTP]")
            result
        } catch (e: Exception) {
            Log.e("NotificationRedactor", "Error during redaction", e)
            "[REDACTED_ERROR]"
        }
    }

    @JvmStatic
    fun redactTitle(title: String?): String = redact(title)

    @JvmStatic
    fun redactContent(content: String?): String = redact(content)
}
