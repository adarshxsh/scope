package com.scope.attentions

import android.util.Log
import java.security.MessageDigest

/**
 * Utility for redacting sensitive PII, OTPs, financial details, credentials,
 * and personal data from notification titles and content before writing to logcat or diagnostic logs.
 */
object NotificationRedactor {

    private val CREDIT_CARD_REGEX = Regex(
        "\\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|6(?:011|5[0-9]{2})[0-9]{12}|[0-9]{4}[-\\s][0-9]{4}[-\\s][0-9]{4}[-\\s][0-9]{4})\\b"
    )

    private val PHONE_REGEX = Regex(
        "\\b(?:\\+?\\d{1,3}[-.\\s]?)?\\(?\\d{3}\\)?[-.\\s]?\\d{3}[-.\\s]?\\d{4}\\b"
    )

    private val EMAIL_REGEX = Regex(
        "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"
    )

    private val URL_REGEX = Regex(
        "https?://[^\\s]+|www\\.[^\\s]+",
        RegexOption.IGNORE_CASE
    )

    private val MONETARY_REGEX = Regex(
        "(?:[\\$₹€£]|USD|INR|EUR|GBP|Rs\\.?)\\s*[\\d,]+(?:\\.\\d{1,2})?|\\b[\\d,]+(?:\\.\\d{1,2})?\\s*(?:USD|INR|EUR|GBP|dollars|rupees|Rs\\.?)",
        RegexOption.IGNORE_CASE
    )

    private val AUTH_TOKEN_REGEX = Regex(
        "(?i)\\b(?:bearer|token|auth|secret|api[_-]?key|access[_-]?token)\\b[:\\s=]+[a-zA-Z0-9_.-]{16,}|\\beyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\b"
    )

    private val OTP_KEYWORD_REGEX = Regex(
        "(?i)\\b(?:otp|code|verification|passcode|v-code|pin)\\b[\\s:=-]*(?:is|code|#|=)?\\s*([0-9]{4,8}|[0-9A-Z]{6,8})\\b"
    )

    private val STANDALONE_OTP_REGEX = Regex(
        "\\b[0-9]{4,8}\\b"
    )

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
            redactSensitivePatterns(text)
        } catch (e: Exception) {
            Log.e("NotificationRedactor", "Error during redaction", e)
            "[REDACTED_ERROR]"
        }
    }

    /**
     * Redacts sensitive details from notification title for safe logcat output.
     *
     * @param title Raw title CharSequence or String
     * @return Redacted title String safe for logging
     */
    @JvmStatic
    fun redactTitle(title: CharSequence?): String {
        if (title.isNullOrBlank()) {
            return "[EMPTY_TITLE]"
        }
        return try {
            redactSensitivePatterns(title.toString())
        } catch (e: Exception) {
            "[REDACTED_TITLE_ERROR]"
        }
    }

    /**
     * Redacts any arbitrary text (e.g. content) using sensitive pattern matching.
     */
    @JvmStatic
    fun redactContent(content: CharSequence?): String {
        if (content.isNullOrBlank()) {
            return ""
        }
        return try {
            redactSensitivePatterns(content.toString())
        } catch (e: Exception) {
            "[REDACTED_TEXT_ERROR]"
        }
    }

    @JvmStatic
    fun redactText(text: CharSequence?): String = redactContent(text)

    /**
     * Applies pattern replacement for OTPs, credit cards, tokens, emails, phone numbers, URLs, amounts.
     */
    @JvmStatic
    fun redactSensitivePatterns(input: String): String {
        var result = input

        // 1. Redact credit cards
        result = CREDIT_CARD_REGEX.replace(result, "[REDACTED_CARD]")

        // 2. Redact phone numbers
        result = PHONE_REGEX.replace(result, "[REDACTED_PHONE]")

        // 3. Redact emails
        result = EMAIL_REGEX.replace(result, "[REDACTED_EMAIL]")

        // 4. Redact URLs
        result = URL_REGEX.replace(result, "[REDACTED_URL]")

        // 5. Redact monetary amounts
        result = MONETARY_REGEX.replace(result, "[REDACTED_AMOUNT]")

        // 6. Redact auth tokens
        result = AUTH_TOKEN_REGEX.replace(result, "[REDACTED_TOKEN]")

        // 7. Redact OTP with keywords
        result = OTP_KEYWORD_REGEX.replace(result) { matchResult ->
            val fullMatch = matchResult.value
            val capturedCode = matchResult.groupValues[1]
            val prefix = fullMatch.substring(0, fullMatch.lastIndexOf(capturedCode))
            "$prefix[REDACTED_OTP]"
        }

        // 8. Redact standalone OTP digits if standalone and not part of previously redacted placeholders
        if (!result.contains("[REDACTED_")) {
            result = STANDALONE_OTP_REGEX.replace(result, "[REDACTED_OTP]")
        }

        return result
    }

    /**
     * Hashes package name for safe diagnostic logging.
     */
    @JvmStatic
    fun hashPackageName(packageName: String?): String {
        if (packageName.isNullOrBlank()) return "unknown"
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            val hashBytes = digest.digest(packageName.toByteArray(Charsets.UTF_8))
            hashBytes.take(4).joinToString("") { "%02x".format(it) }
        } catch (e: Exception) {
            "pkg_hash_err"
        }
    }
}
