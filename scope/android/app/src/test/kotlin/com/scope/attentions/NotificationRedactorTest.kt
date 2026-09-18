package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Test

class NotificationRedactorTest {

    @Test
    fun testRedactOtpCodes() {
        assertEquals(
            "Your login OTP is [REDACTED_OTP]",
            NotificationRedactor.redact("Your login OTP is 849201")
        )
        assertEquals(
            "Use code [REDACTED_OTP] to verify",
            NotificationRedactor.redact("Use code 1234 to verify")
        )
        assertEquals(
            "Security code: [REDACTED_OTP]",
            NotificationRedactor.redact("Security code: 12345678")
        )
    }

    @Test
    fun testRedactCreditCardNumbers() {
        assertEquals(
            "Card ending [REDACTED_PII] was charged",
            NotificationRedactor.redact("Card ending 4532 1122 3344 5566 was charged")
        )
        assertEquals(
            "Card [REDACTED_PII] updated",
            NotificationRedactor.redact("Card 4532-1122-3344-5566 updated")
        )
        assertEquals(
            "Account [REDACTED_PII] transaction complete",
            NotificationRedactor.redact("Account 4532112233445566 transaction complete")
        )
    }

    @Test
    fun testRedactEmailAddresses() {
        assertEquals(
            "Contact [REDACTED_PII] for support",
            NotificationRedactor.redact("Contact user@example.com for support")
        )
        assertEquals(
            "Invoice sent to [REDACTED_PII]",
            NotificationRedactor.redact("Invoice sent to john.doe@company.co.uk")
        )
    }

    @Test
    fun testRedactMonetaryBalances() {
        assertEquals(
            "Your balance is [REDACTED_PII]",
            NotificationRedactor.redact("Your balance is $1,250.50")
        )
        assertEquals(
            "Payment of [REDACTED_PII] received",
            NotificationRedactor.redact("Payment of ₹500 received")
        )
        assertEquals(
            "Debited [REDACTED_PII] from account",
            NotificationRedactor.redact("Debited Rs. 1,000 from account")
        )
        assertEquals(
            "Transferred [REDACTED_PII] successfully",
            NotificationRedactor.redact("Transferred 500 USD successfully")
        )
        assertEquals(
            "Price: [REDACTED_PII]",
            NotificationRedactor.redact("Price: €99.99")
        )
    }

    @Test
    fun testRedactMultipleSensitiveFields() {
        val input = "Sent [REDACTED_PII] to user@example.com with OTP 987654 for card 4532-1122-3344-5566"
        val expected = "Sent [REDACTED_PII] to [REDACTED_PII] with OTP [REDACTED_OTP] for card [REDACTED_PII]"
        assertEquals(
            expected,
            NotificationRedactor.redact("Sent $100.00 to user@example.com with OTP 987654 for card 4532-1122-3344-5566")
        )
    }

    @Test
    fun testNullAndEmptyStrings() {
        assertEquals("", NotificationRedactor.redact(null))
        assertEquals("", NotificationRedactor.redact(""))
    }

    @Test
    fun testNonSensitiveTextRemainsUnchanged() {
        val safeText = "Meeting scheduled at 3 PM tomorrow in Conference Room B."
        assertEquals(safeText, NotificationRedactor.redact(safeText))
    }
}
