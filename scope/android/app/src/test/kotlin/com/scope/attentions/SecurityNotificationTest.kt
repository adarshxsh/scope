package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SecurityNotificationTest {

    @Test
    fun testNotificationRedactor_OTPMasking() {
        val input1 = "Your verification code is 482910."
        val redacted1 = NotificationRedactor.redact(input1)
        assertTrue("Redacted output should contain [REDACTED_OTP]: $redacted1", redacted1.contains("[REDACTED_OTP]"))
        assertTrue("Redacted output should not contain raw passcode: $redacted1", !redacted1.contains("482910"))

        val input2 = "Your OTP is 1234"
        val redacted2 = NotificationRedactor.redact(input2)
        assertTrue("Redacted output should contain [REDACTED_OTP]: $redacted2", redacted2.contains("[REDACTED_OTP]"))
    }

    @Test
    fun testNotificationRedactor_CreditCardMasking() {
        val input = "Payment processed for card 4532 1234 5678 9010"
        val redacted = NotificationRedactor.redact(input)
        assertTrue("Redacted output should contain [REDACTED_CARD]: $redacted", redacted.contains("[REDACTED_CARD]"))
        assertTrue("Redacted output should not contain full card number: $redacted", !redacted.contains("4532 1234 5678 9010"))
    }

    @Test
    fun testNotificationRedactor_TokenMasking() {
        val input = "Secret token: ab12cd34ef56gh78"
        val redacted = NotificationRedactor.redact(input)
        assertTrue("Redacted output should contain [REDACTED_TOKEN]: $redacted", redacted.contains("[REDACTED_TOKEN]"))
        assertTrue("Redacted output should not contain full secret: $redacted", !redacted.contains("ab12cd34ef56gh78"))
    }

    @Test
    fun testCryptoManager_EncryptionAndDecryption() {
        val plainText = "Sensitive Bank Alert: OTP 998877"
        val encrypted = CryptoManager.encrypt(plainText)

        assertNotEquals("Encrypted text must not equal plaintext", plainText, encrypted)
        assertTrue("Encrypted text should be Base64 string", encrypted.isNotEmpty())

        val decrypted = CryptoManager.decrypt(encrypted)
        assertEquals("Decrypted text must match original plaintext", plainText, decrypted)
    }

    @Test
    fun testCryptoManager_RandomIV() {
        val plainText = "Test Payload"
        val encrypted1 = CryptoManager.encrypt(plainText)
        val encrypted2 = CryptoManager.encrypt(plainText)

        assertNotEquals("Subsequent encryptions should produce unique ciphertexts (due to random IV)", encrypted1, encrypted2)
        assertEquals(plainText, CryptoManager.decrypt(encrypted1))
        assertEquals(plainText, CryptoManager.decrypt(encrypted2))
    }

    @Test
    fun testInMemoryPayloadEncryptionAndDrainQueue() {
        val rawTitle = "Bank Verification"
        val rawContent = "Your passcode is 654321"

        // 1. Redact
        val redactedTitle = NotificationRedactor.redact(rawTitle)
        val redactedContent = NotificationRedactor.redact(rawContent)

        // 2. Encrypt
        val encryptedTitle = CryptoManager.encrypt(redactedTitle)
        val encryptedContent = CryptoManager.encrypt(redactedContent)

        // Verify memory buffer holds encrypted text, NOT plaintext
        assertNotEquals(rawContent, encryptedContent)
        assertNotEquals(redactedContent, encryptedContent)
        assertTrue(!encryptedContent.contains("654321"))
        assertTrue(!encryptedContent.contains("[REDACTED_OTP]"))

        // Create in-memory queued item
        val queuedItem = NotificationData(
            id = "notif_100",
            packageName = "com.bank.app",
            title = encryptedTitle,
            content = encryptedContent,
            timestamp = System.currentTimeMillis(),
            category = "msg",
            isOngoing = false
        )

        // Memory buffer inspection: queuedItem fields are encrypted
        assertTrue(queuedItem.title != rawTitle)
        assertTrue(queuedItem.content != rawContent)

        // 3. Decrypt on drain
        val decryptedTitle = CryptoManager.decrypt(queuedItem.title)
        val decryptedContent = CryptoManager.decrypt(queuedItem.content)

        assertEquals("Bank Verification", decryptedTitle)
        assertEquals("Your passcode is [REDACTED_OTP]", decryptedContent)
    }
}
