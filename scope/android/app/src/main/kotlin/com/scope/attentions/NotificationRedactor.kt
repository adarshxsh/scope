package com.scope.attentions

import java.util.regex.Pattern

/**
 * Regex-based redaction engine that automatically detects and masks sensitive patterns
 * such as OTPs/passcodes, credit card numbers, and secret tokens in notification content.
 */
object NotificationRedactor {

    // Credit card pattern: 13-19 digits, optionally separated by spaces or hyphens
    private val CREDIT_CARD_PATTERN = Pattern.compile("\\b(?:\\d[ -]*?){13,19}\\b")

    // Secret tokens / API keys / bearer tokens / passwords
    private val TOKEN_PATTERN = Pattern.compile("(?i)\\b(token|secret|bearer|api[_-]?key|auth[_-]?code|password)\\s*[:=]\\s*([a-zA-Z0-9_-]{8,})")

    // Standalone 32+ hex character secret tokens
    private val HEX_TOKEN_PATTERN = Pattern.compile("\\b[a-fA-F0-9]{32,64}\\b")

    // Contextual OTP / Passcode pattern: e.g. "code is 123456", "OTP: 9876", "passcode 482910"
    private val CONTEXTUAL_OTP_PATTERN = Pattern.compile("(?i)(\\b(?:code|otp|passcode|pin|verification|v-code|auth)\\b\\s*(?:is|:|=)?\\s*)\\d{4,8}\\b")

    // General standalone 4 to 8 digit numbers (passcodes/OTPs)
    private val STANDALONE_OTP_PATTERN = Pattern.compile("\\b\\d{4,8}\\b")

    /**
     * Redacts sensitive information from text.
     */
    fun redact(text: String?): String {
        if (text.isNullOrEmpty()) return ""

        var result = text

        // 1. Redact credit card numbers
        result = CREDIT_CARD_PATTERN.matcher(result).replaceAll("[REDACTED_CARD]")

        // 2. Redact key-value tokens
        result = TOKEN_PATTERN.matcher(result).replaceAll("$1: [REDACTED_TOKEN]")

        // 3. Redact hex tokens
        result = HEX_TOKEN_PATTERN.matcher(result).replaceAll("[REDACTED_TOKEN]")

        // 4. Redact contextual OTPs
        result = CONTEXTUAL_OTP_PATTERN.matcher(result).replaceAll("$1[REDACTED_OTP]")

        // 5. Redact remaining standalone 4-8 digit OTPs / passcodes
        result = STANDALONE_OTP_PATTERN.matcher(result).replaceAll("[REDACTED_OTP]")

        return result
    }
}
