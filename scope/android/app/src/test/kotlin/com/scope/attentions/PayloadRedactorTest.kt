package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Test

class PayloadRedactorTest {

    @Test
    fun testRedactOtpPasscode() {
        val input = "Your verification code is 882715. Valid for 10 minutes."
        val expected = "Your verification code is [REDACTED]. Valid for 10 minutes."
        val actual = PayloadRedactor.redact(input)
        assertEquals(expected, actual)
    }

    @Test
    fun testRedactContextualToken() {
        val input = "Your login OTP: 987654. Do not share this secret."
        val expected = "Your login OTP: [REDACTED]. Do not share this secret."
        val actual = PayloadRedactor.redact(input)
        assertEquals(expected, actual)
    }

    @Test
    fun testRedactCreditCardNumber() {
        val input = "Your card 4111 2222 3333 4444 was charged $50.00"
        val expected = "Your card [REDACTED] was charged $50.00"
        val actual = PayloadRedactor.redact(input)
        assertEquals(expected, actual)
    }

    @Test
    fun testRedactFinancialAccount() {
        val input = "Account acct-987654321 credited with $1000"
        val expected = "Account [REDACTED] credited with $1000"
        val actual = PayloadRedactor.redact(input)
        assertEquals(expected, actual)
    }

    @Test
    fun testNonSensitiveTextUnchanged() {
        val input = "Meeting scheduled at 3 PM with Team"
        val expected = "Meeting scheduled at 3 PM with Team"
        val actual = PayloadRedactor.redact(input)
        assertEquals(expected, actual)
    }

    @Test
    fun testNullAndEmptyInput() {
        assertEquals("", PayloadRedactor.redact(null))
        assertEquals("", PayloadRedactor.redact(""))
    }

    @Test
    fun testPerformanceUnder2ms() {
        val input = "Your OTP passcode is 123456 for bank account acct-0001234567. Card 4111-2222-3333-4444."
        val startTime = System.nanoTime()
        for (i in 0 until 100) {
            PayloadRedactor.redact(input)
        }
        val durationMs = (System.nanoTime() - startTime) / 1_000_000.0 / 100.0
        assert(durationMs < 2.0) { "Redaction took $durationMs ms, exceeding 2ms threshold" }
    }
}
