package com.scope.attentions

import android.util.Log
import java.util.regex.Matcher
import java.util.regex.Pattern

/**
 * Centralized PrivacyLogger helper for native Android code.
 *
 * Evaluates log messages against entity extraction regexes to redact sensitive data
 * (OTPs, monetary amounts, emails, phone numbers, account/order/transaction IDs)
 * before writing output to system logcat buffers.
 */
object PrivacyLogger {

    private val emailPattern = Pattern.compile(
        "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}\\b"
    )

    private val phonePattern = Pattern.compile(
        "\\b(?:\\+?\\d{1,3}[-.\\s]?)?\\(?\\d{3,4}\\)?[-.\\s]?\\d{3,4}[-.\\s]?\\d{4}\\b|\\b1800[-.\\s]?[A-Z0-9]{3,4}[-.\\s]?[A-Z0-9]{4}\\b",
        Pattern.CASE_INSENSITIVE
    )

    private val amountPattern = Pattern.compile(
        "(?:₹|rs\\.?|inr|usd|\\$|eur|€|gbp|£|aed)\\s*([0-9]+(?:,[0-9]{2,3})*(?:\\.[0-9]{1,2})?|[0-9]+(?:\\.[0-9]{1,2})?)|([0-9]+(?:,[0-9]{2,3})*(?:\\.[0-9]{1,2})?)\\s*(?:rs\\.?|inr|usd|eur|gbp|aed)",
        Pattern.CASE_INSENSITIVE
    )

    private val accountAndIdPattern = Pattern.compile(
        "\\b(?:acc|account|a/c|txn|txnid|transaction|utr|upi|order|ord|ref|reference|tracking|awb|shipment|coupon|promo code|voucher)[\\s#:.-]*[A-Z0-9-]{4,}\\b",
        Pattern.CASE_INSENSITIVE
    )

    private val otpDigitsPattern = Pattern.compile("\\b\\d{4,8}\\b")

    /**
     * Synchronously sanitizes input text by replacing sensitive entities with category tokens.
     */
    fun sanitize(input: String?): String {
        if (input.isNullOrEmpty()) return input ?: ""

        var text = input

        // 1. Emails
        text = emailPattern.matcher(text).replaceAll("[EMAIL]")

        // 2. Phone Numbers
        text = phonePattern.matcher(text).replaceAll("[PHONE]")

        // 3. Amounts
        text = amountPattern.matcher(text).replaceAll("[AMOUNT]")

        // 4. Account/Order/Txn IDs
        text = accountAndIdPattern.matcher(text).replaceAll("[ACCOUNT]")

        // 5. OTPs (excluding years 2020..2030)
        val matcher = otpDigitsPattern.matcher(text)
        val sb = StringBuffer()
        while (matcher.find()) {
            val value = matcher.group()
            val number = value.toIntOrNull()
            if (number != null && number in 2020..2030) {
                matcher.appendReplacement(sb, Matcher.quoteReplacement(value))
            } else {
                matcher.appendReplacement(sb, Matcher.quoteReplacement("[OTP]"))
            }
        }
        matcher.appendTail(sb)

        return sb.toString()
    }

    fun d(tag: String, message: String) {
        Log.d(tag, sanitize(message))
    }

    fun i(tag: String, message: String) {
        Log.i(tag, sanitize(message))
    }

    fun w(tag: String, message: String) {
        Log.w(tag, sanitize(message))
    }

    fun e(tag: String, message: String, tr: Throwable? = null) {
        if (tr != null) {
            Log.e(tag, sanitize(message), tr)
        } else {
            Log.e(tag, sanitize(message))
        }
    }
}
