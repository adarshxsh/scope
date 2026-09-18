package com.scope.attentions

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

    private val AUTH_TOKEN_REGEX = Regex(
        "(?i)\\b(?:bearer|token|auth|secret|api[_-]?key|access[_-]?token)\\b[:\\s=]+[a-zA-Z0-9_.-]{16,}"
    )

    private val OTP_KEYWORD_REGEX = Regex(
        "(?i)\\b(?:otp|code|verification|passcode|v-code|pin)\\b[\\s:=-]*(?:is|code|#|=)?\\s*([0-9]{4,8}|[0-9A-Z]{6,8})\\b"
    )

    private val STANDALONE_OTP_REGEX = Regex(
        "\\b[0-9]{4,8}\\b"
    )

    /**
     * Redacts sensitive details from notification title for safe logcat output.
     *
     * @param title Raw title CharSequence or String
     * @return Redacted title String safe for logging
     */
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
    fun redactText(text: CharSequence?): String {
        if (text.isNullOrBlank()) {
            return ""
        }
        return try {
            redactSensitivePatterns(text.toString())
        } catch (e: Exception) {
            "[REDACTED_TEXT_ERROR]"
        }
    }

    /**
     * Applies pattern replacement for OTPs, credit cards, tokens, emails, phone numbers.
     */
    fun redactSensitivePatterns(input: String): String {
        var result = input

        // 1. Redact credit cards
        result = CREDIT_CARD_REGEX.replace(result, "[REDACTED_CARD]")

        // 2. Redact phone numbers
        result = PHONE_REGEX.replace(result, "[REDACTED_PHONE]")

        // 3. Redact emails
        result = EMAIL_REGEX.replace(result, "[REDACTED_EMAIL]")

        // 4. Redact auth tokens
        result = AUTH_TOKEN_REGEX.replace(result, "[REDACTED_TOKEN]")

        // 5. Redact OTP with keywords
        result = OTP_KEYWORD_REGEX.replace(result) { matchResult ->
            val fullMatch = matchResult.value
            val capturedCode = matchResult.groupValues[1]
            val prefix = fullMatch.substring(0, fullMatch.lastIndexOf(capturedCode))
            "$prefix[REDACTED_OTP]"
        }

        // 6. Redact standalone OTP digits if standalone and not part of previously redacted placeholders
        if (!result.contains("[REDACTED_")) {
            result = STANDALONE_OTP_REGEX.replace(result, "[REDACTED_OTP]")
        }

        return result
    }

    /**
     * Hashes package name for safe diagnostic logging.
     */
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
