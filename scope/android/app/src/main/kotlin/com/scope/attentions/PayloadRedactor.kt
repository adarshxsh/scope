package com.scope.attentions

/**
 * High-performance rule-based regex redaction utility for sensitive notification payloads.
 *
 * Scans notification titles and contents for sensitive information such as:
 *   - OTP passcodes and verification codes
 *   - Credit card numbers and financial digits
 *   - Secret tokens, API keys, PINs, and authentication secrets
 *
 * Execution target: < 2ms per event.
 */
object PayloadRedactor {

    // Credit card numbers (13 to 19 digits, optional spaces/hyphens)
    private val CREDIT_CARD_REGEX = Regex("""\b(?:\d[ -]*?){13,19}\b""")

    // Contextual sensitive tokens (e.g., "code is 123456", "OTP: 987654", "token = xyz123")
    private val CONTEXTUAL_TOKEN_REGEX = Regex(
        """(?i)(\b(?:otp|code|passcode|pin|verification|verify|v-code|secret|token|auth|password|key|cvv|cvc|ssn|account|acct)\b[\s:=#-]*)([a-zA-Z0-9_-]{4,32})"""
    )

    // Standalone 4-8 digit numeric codes (OTP codes, PINs, financial digits)
    private val NUMERIC_CODE_REGEX = Regex("""\b\d{4,8}\b""")

    /**
     * Scans and redacts sensitive patterns from the provided text string.
     * Returns the redacted text with sensitive portions replaced by [REDACTED].
     */
    fun redact(input: String?): String {
        if (input.isNullOrEmpty()) {
            return ""
        }

        var result = input

        // 1. Redact credit card numbers
        result = CREDIT_CARD_REGEX.replace(result, "[REDACTED]")

        // 2. Redact contextual secrets/tokens (preserves keyword prefix, redacts secret value)
        result = CONTEXTUAL_TOKEN_REGEX.replace(result) { matchResult ->
            "${matchResult.groupValues[1]}[REDACTED]"
        }

        // 3. Redact standalone 4-8 digit codes (OTPs, PINs, financial digits)
        result = NUMERIC_CODE_REGEX.replace(result, "[REDACTED]")

        return result
    }
}
