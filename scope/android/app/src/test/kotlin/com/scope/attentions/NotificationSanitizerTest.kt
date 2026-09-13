package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.MessageDigest

class NotificationSanitizerTest {

    @Test
    fun testHashTitle_nullOrEmpty() {
        assertEquals("", NotificationSanitizer.hashTitle(null))
        assertEquals("", NotificationSanitizer.hashTitle(""))
    }

    @Test
    fun testHashTitle_validTitleLengthAndContent() {
        val title = "Your verification code is 123456"
        val hash = NotificationSanitizer.hashTitle(title)

        // Must be exactly 8 hex characters
        assertEquals(8, hash.length)
        assertTrue(hash.matches(Regex("^[0-9a-f]{8}$")))

        // Verify SHA-256 calculation match
        val expectedDigest = MessageDigest.getInstance("SHA-256")
            .digest(title.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
            .take(8)

        assertEquals(expectedDigest, hash)
    }

    @Test
    fun testHashTitle_latencyConstraint() {
        val title = "Urgent: Bank Account Balance Alert"
        
        // Warm up JVM
        repeat(100) { NotificationSanitizer.hashTitle(title) }

        val start = System.nanoTime()
        repeat(1000) { NotificationSanitizer.hashTitle(title) }
        val elapsedNanos = System.nanoTime() - start
        
        val averageMs = (elapsedNanos / 1000.0) / 1_000_000.0
        // Guardrail constraint: < 0.2ms latency per call
        assertTrue("Latency per call was ${averageMs}ms, expected < 0.2ms", averageMs < 0.2)
    }

    @Test
    fun testLogDebug_disabledInReleaseBuilds() {
        var lambdaExecuted = false

        NotificationSanitizer.logDebug(
            tag = "TestTag",
            messageSupplier = {
                lambdaExecuted = true
                "Secret Title Hash"
            },
            isDebug = false
        )

        // Lambda should NOT be evaluated when isDebug is false
        assertFalse("Message supplier lambda should not be executed when isDebug is false", lambdaExecuted)
    }

    @Test
    fun testLogDebug_enabledInDebugBuilds() {
        var lambdaExecuted = false

        NotificationSanitizer.logDebug(
            tag = "TestTag",
            messageSupplier = {
                lambdaExecuted = true
                "Secret Title Hash"
            },
            isDebug = true
        )

        // Lambda SHOULD be evaluated when isDebug is true
        assertTrue("Message supplier lambda should be executed when isDebug is true", lambdaExecuted)
    }
}
