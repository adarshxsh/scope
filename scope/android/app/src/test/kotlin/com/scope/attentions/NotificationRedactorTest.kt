package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationRedactorTest {

    @Test
    fun testNullAndEmptyInputs() {
        assertEquals("", NotificationRedactor.redact(null))
        assertEquals("", NotificationRedactor.redact(""))
        assertEquals("[EMPTY_TITLE]", NotificationRedactor.redactTitle(null))
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
    fun testRedactTitleWithOtp() {
        val input = "Your OTP code is 123456 for Bank login"
        val redacted = NotificationRedactor.redactTitle(input)
        assertTrue(redacted.contains("[REDACTED_OTP]"))
        assertTrue(!redacted.contains("123456"))
    }

    @Test
    fun testRedactTitleWithStandaloneDigits() {
        val input = "849201"
        val redacted = NotificationRedactor.redactTitle(input)
        assertEquals("[REDACTED_OTP]", redacted)
    }

    @Test
    fun testRedactTitleWithCreditCard() {
        val input = "Card 4532 1111 2222 3333 charged $50.00"
        val redacted = NotificationRedactor.redactTitle(input)
        assertTrue(redacted.contains("[REDACTED_CARD]"))
        assertTrue(!redacted.contains("4532"))
    }

    @Test
    fun testRedactTitleWithAuthToken() {
        val input = "Bearer token: secret1234567890abcdef"
        val redacted = NotificationRedactor.redactTitle(input)
        assertTrue(redacted.contains("[REDACTED_TOKEN]"))
        assertTrue(!redacted.contains("secret1234567890abcdef"))
    }

    @Test
    fun testRedactTitleWithEmailAndPhone() {
        val input = "Contact user@example.com or call +1-555-123-4567"
        val redacted = NotificationRedactor.redactTitle(input)
        assertTrue(redacted.contains("[REDACTED_EMAIL]"))
        assertTrue(redacted.contains("[REDACTED_PHONE]"))
        assertTrue(!redacted.contains("user@example.com"))
        assertTrue(!redacted.contains("555-123-4567"))
    }

    @Test
    fun testRedactTitleNullAndEmpty() {
        assertEquals("[EMPTY_TITLE]", NotificationRedactor.redactTitle(null))
        assertEquals("[EMPTY_TITLE]", NotificationRedactor.redactTitle(""))
        assertEquals("[EMPTY_TITLE]", NotificationRedactor.redactTitle("   "))
    }

    @Test
    fun testRedactTitleNormalTitle() {
        val input = "Meeting with Design Team"
        val redacted = NotificationRedactor.redactTitle(input)
        assertEquals("Meeting with Design Team", redacted)
    }

    @Test
    fun testHashPackageName() {
        val pkg = "com.google.android.gm"
        val hashed = NotificationRedactor.hashPackageName(pkg)
        assertTrue(hashed.length == 8)
        assertEquals("unknown", NotificationRedactor.hashPackageName(null))
        assertEquals("unknown", NotificationRedactor.hashPackageName(""))
    }
}
