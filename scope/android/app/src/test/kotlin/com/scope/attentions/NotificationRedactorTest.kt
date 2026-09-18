package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Test

class NotificationRedactorTest {

    @Test
    fun testRedactNullAndEmpty() {
        assertEquals("", NotificationRedactor.redact(null))
        assertEquals("", NotificationRedactor.redact(""))
    }

    @Test
    fun testRedactOtp() {
        val input = "Your OTP is 654321"
        val expected = "Your OTP is [REDACTED_OTP]"
        assertEquals(expected, NotificationRedactor.redact(input))
    }

    @Test
    fun testRedactEmail() {
        val input = "Send confirmation to john.doe@example.com now"
        val expected = "Send confirmation to [REDACTED_EMAIL] now"
        assertEquals(expected, NotificationRedactor.redact(input))
    }

    @Test
    fun testRedactPhone() {
        val input = "Call +1 555-987-6543"
        val expected = "Call [REDACTED_PHONE]"
        assertEquals(expected, NotificationRedactor.redact(input))
    }

    @Test
    fun testRedactMoney() {
        val input = "Charged $99.99 on your card"
        val expected = "Charged [REDACTED_MONEY] on your card"
        assertEquals(expected, NotificationRedactor.redact(input))
    }

    @Test
    fun testRedactUrl() {
        val input = "Visit https://secure.bank.com/auth"
        val expected = "Visit [REDACTED_URL]"
        assertEquals(expected, NotificationRedactor.redact(input))
    }

    @Test
    fun testRedactToken() {
        val input = "Auth token: Bearer eyJhbGciOiJIUzI1NiJ9"
        val expected = "Auth token: [REDACTED_TOKEN]"
        assertEquals(expected, NotificationRedactor.redact(input))
    }

    @Test
    fun testCleanTextUnchanged() {
        val input = "System update ready"
        assertEquals(input, NotificationRedactor.redact(input))
    }
}
