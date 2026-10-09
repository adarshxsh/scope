package com.scope.attentions

/**
 * Privacy guardrail utility for redacting sensitive notification text
 * before sending to Android logcat or telemetry.
 */
object Redactor {
    @JvmStatic
    fun redact(text: String?): String {
        if (text.isNullOrBlank()) {
            return "[EMPTY]"
        }
        return "[REDACTED len=${text.length}]"
    }
}
