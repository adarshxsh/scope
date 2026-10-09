package com.scope.attentions

import org.junit.Assert.*
import org.junit.Test

class NotificationRedactorTest {

    @Test
    fun testNullAndEmptyInputs() {
        assertEquals("", NotificationRedactor.redact(null))
        assertEquals("", NotificationRedactor.redact(""))
        assertEquals("", NotificationRedactor.redactTitle(null))
        assertEquals("", NotificationRedactor.redactContent(""))
    }

    @Test
    fun testCleanText() {
        val clean = "Meeting scheduled at 3:00 PM in Room B"
        assertEquals(clean, NotificationRedactor.redact(clean))
    }

    @Test
    fun testOtpRedaction() {
        val text = "Your login code is 549102. Do not share."
        val redacted = NotificationRedactor.redact(text)
        assertTrue(redacted.contains("[REDACTED_OTP]"))
        assertFalse(redacted.contains("549102"))
    }

    @Test
    fun testCardRedaction() {
        val text = "Card 5412-7512-3412-9081 debited."
        val redacted = NotificationRedactor.redact(text)
        assertTrue(redacted.contains("[REDACTED_CARD]"))
        assertFalse(redacted.contains("5412-7512-3412-9081"))
    }

    @Test
    fun testEmailRedaction() {
        val text = "Email sent to john.doe@example.com successfully"
        val redacted = NotificationRedactor.redact(text)
        assertTrue(redacted.contains("[REDACTED_EMAIL]"))
        assertFalse(redacted.contains("john.doe@example.com"))
    }

    @Test
    fun testUrlRedaction() {
        val text = "Please visit https://secure.bank.com/auth to verify."
        val redacted = NotificationRedactor.redact(text)
        assertTrue(redacted.contains("[REDACTED_URL]"))
        assertFalse(redacted.contains("https://secure.bank.com/auth"))
    }

    @Test
    fun testMonetaryRedaction() {
        val text = "Payment of $1,250.00 received."
        val redacted = NotificationRedactor.redact(text)
        assertTrue(redacted.contains("[REDACTED_AMOUNT]"))
        assertFalse(redacted.contains("1,250.00"))
    }

    @Test
    fun testRedactMultipleSensitiveFields() {
        val input = "Sent $100.00 to user@example.com with OTP 987654 for card 4532-1122-3344-5566"
        val redacted = NotificationRedactor.redact(input)
        assertTrue(redacted.contains("[REDACTED_AMOUNT]"))
        assertTrue(redacted.contains("[REDACTED_EMAIL]"))
        assertTrue(redacted.contains("[REDACTED_OTP]"))
        assertTrue(redacted.contains("[REDACTED_CARD]"))
        assertFalse(redacted.contains("100.00"))
        assertFalse(redacted.contains("user@example.com"))
        assertFalse(redacted.contains("987654"))
        assertFalse(redacted.contains("4532-1122-3344-5566"))
    }
}
