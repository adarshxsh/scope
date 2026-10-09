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

        val redactedTitle = NotificationRedactor.redactTitle("Security OTP 549102")
        assertTrue(redactedTitle.contains("[REDACTED_OTP]"))
        assertFalse(redactedTitle.contains("549102"))

        val redactedContent = NotificationRedactor.redactContent("Your OTP is 549102")
        assertTrue(redactedContent.contains("[REDACTED_OTP]"))
        assertFalse(redactedContent.contains("549102"))
    }

    @Test
    fun testCardRedaction() {
        val text = "Card 5412-7512-3412-9081 debited."
        val redacted = NotificationRedactor.redact(text)
        assertTrue(redacted.contains("[REDACTED_CARD]"))
        assertFalse(redacted.contains("5412-7512-3412-9081"))

        val redactedTitle = NotificationRedactor.redactTitle("Card 5412-7512-3412-9081 Notice")
        assertTrue(redactedTitle.contains("[REDACTED_CARD]"))
        assertFalse(redactedTitle.contains("5412-7512-3412-9081"))

        val redactedContent = NotificationRedactor.redactContent("Your card 5412-7512-3412-9081 was charged.")
        assertTrue(redactedContent.contains("[REDACTED_CARD]"))
        assertFalse(redactedContent.contains("5412-7512-3412-9081"))
    }

    @Test
    fun testEmailRedaction() {
        val text = "Email sent to john.doe@example.com successfully"
        val redacted = NotificationRedactor.redact(text)
        assertTrue(redacted.contains("[REDACTED_EMAIL]"))
        assertFalse(redacted.contains("john.doe@example.com"))

        val redactedTitle = NotificationRedactor.redactTitle("Alert for john.doe@example.com")
        assertTrue(redactedTitle.contains("[REDACTED_EMAIL]"))
        assertFalse(redactedTitle.contains("john.doe@example.com"))

        val redactedContent = NotificationRedactor.redactContent("Contact john.doe@example.com for info")
        assertTrue(redactedContent.contains("[REDACTED_EMAIL]"))
        assertFalse(redactedContent.contains("john.doe@example.com"))
    }

    @Test
    fun testPhoneRedaction() {
        val text = "Call us at +1-555-123-4567 for assistance"
        val redacted = NotificationRedactor.redact(text)
        assertTrue(redacted.contains("[REDACTED_PHONE]"))
        assertFalse(redacted.contains("555-123-4567"))

        val redactedTitle = NotificationRedactor.redactTitle("Callback request +1-555-123-4567")
        assertTrue(redactedTitle.contains("[REDACTED_PHONE]"))
        assertFalse(redactedTitle.contains("555-123-4567"))

        val redactedContent = NotificationRedactor.redactContent("Reach out at (555) 123-4567")
        assertTrue(redactedContent.contains("[REDACTED_PHONE]"))
        assertFalse(redactedContent.contains("123-4567"))
    }

    @Test
    fun testUrlRedaction() {
        val text = "Please visit https://secure.bank.com/auth to verify."
        val redacted = NotificationRedactor.redact(text)
        assertTrue(redacted.contains("[REDACTED_URL]"))
        assertFalse(redacted.contains("https://secure.bank.com/auth"))

        val redactedTitle = NotificationRedactor.redactTitle("Login at http://bank.com/login")
        assertTrue(redactedTitle.contains("[REDACTED_URL]"))
        assertFalse(redactedTitle.contains("http://bank.com/login"))

        val redactedContent = NotificationRedactor.redactContent("Open www.example.com to view")
        assertTrue(redactedContent.contains("[REDACTED_URL]"))
        assertFalse(redactedContent.contains("www.example.com"))
    }

    @Test
    fun testMonetaryRedaction() {
        val text = "Payment of $1,250.00 received."
        val redacted = NotificationRedactor.redact(text)
        assertTrue(redacted.contains("[REDACTED_AMOUNT]"))
        assertFalse(redacted.contains("1,250.00"))

        val redactedTitle = NotificationRedactor.redactTitle("Debit of $500.00")
        assertTrue(redactedTitle.contains("[REDACTED_AMOUNT]"))
        assertFalse(redactedTitle.contains("500.00"))

        val redactedContent = NotificationRedactor.redactContent("Transferred USD 250 to account")
        assertTrue(redactedContent.contains("[REDACTED_AMOUNT]"))
        assertFalse(redactedContent.contains("250"))
    }

    @Test
    fun testTokenRedaction() {
        val token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        val text = "Session token $token expires soon"
        val redacted = NotificationRedactor.redact(text)
        assertTrue(redacted.contains("[REDACTED_TOKEN]"))
        assertFalse(redacted.contains(token))

        val redactedTitle = NotificationRedactor.redactTitle("Token $token active")
        assertTrue(redactedTitle.contains("[REDACTED_TOKEN]"))
        assertFalse(redactedTitle.contains(token))

        val redactedContent = NotificationRedactor.redactContent("Your auth bearer is $token")
        assertTrue(redactedContent.contains("[REDACTED_TOKEN]"))
        assertFalse(redactedContent.contains(token))
    }
}
