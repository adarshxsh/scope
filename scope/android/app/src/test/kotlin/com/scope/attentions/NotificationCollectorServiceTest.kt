package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.clearQueue()
        NotificationCollectorService.clearKey()
    }

    @Test
    fun testPayloadEncryptionAndDecryptionRoundTrip() {
        val originalTitle = "Bank Alert: OTP 123456"
        val originalContent = "Your OTP for transfer of $500 is 123456"

        val encryptedTitle = NotificationCollectorService.encryptPayload(originalTitle)
        val encryptedContent = NotificationCollectorService.encryptPayload(originalContent)

        // Verify encryption occurred and raw text is not present in ciphertext
        assertNotEquals(originalTitle, encryptedTitle)
        assertNotEquals(originalContent, encryptedContent)
        assertFalse(encryptedTitle.contains("123456"))
        assertFalse(encryptedContent.contains("123456"))
        assertFalse(encryptedTitle.contains("Bank Alert"))

        // Decrypt and verify round-trip fidelity
        val decryptedTitle = NotificationCollectorService.decryptPayload(encryptedTitle)
        val decryptedContent = NotificationCollectorService.decryptPayload(encryptedContent)

        assertEquals(originalTitle, decryptedTitle)
        assertEquals(originalContent, decryptedContent)
    }

    @Test
    fun testInMemoryQueueHoldsEncryptedPayloadsAndDrainQueueDecrypts() {
        val plainTitle = "Private Message"
        val plainContent = "Meet me at the station at 5 PM"

        val encryptedTitle = NotificationCollectorService.encryptPayload(plainTitle)
        val encryptedContent = NotificationCollectorService.encryptPayload(plainContent)

        val item = NotificationData(
            id = "notif_1",
            packageName = "com.messaging.app",
            title = encryptedTitle,
            content = encryptedContent,
            timestamp = System.currentTimeMillis(),
            category = "msg",
            isOngoing = false
        )

        NotificationCollectorService.enqueueRaw(item)

        // Inspect raw items in queue before drain
        val rawItems = NotificationCollectorService.getRawQueueItems()
        assertEquals(1, rawItems.size)
        val rawInQueue = rawItems[0]

        // Confirm queue memory holds encrypted values, NOT plaintext
        assertNotEquals(plainTitle, rawInQueue.title)
        assertNotEquals(plainContent, rawInQueue.content)
        assertFalse(rawInQueue.title.contains("Private Message"))
        assertFalse(rawInQueue.content.contains("station"))

        // Perform drainQueue()
        val drained = NotificationCollectorService.drainQueue()

        assertEquals(1, drained.size)
        val restoredItem = drained[0]

        // Confirm drainQueue restores plaintext payloads for MethodChannel delivery
        assertEquals(plainTitle, restoredItem.title)
        assertEquals(plainContent, restoredItem.content)

        // Confirm zero residual plaintext data in queue buffer after drain
        assertEquals(0, NotificationCollectorService.queueSize())
    }

    @Test
    fun testKeyErasureZeroesKeyBytes() {
        val secretTitle = "Secret OTP 987654"
        val encryptedTitle = NotificationCollectorService.encryptPayload(secretTitle)

        // Verify it decrypts before key clear
        val decryptedBefore = NotificationCollectorService.decryptPayload(encryptedTitle)
        assertEquals(secretTitle, decryptedBefore)

        // Erase key
        NotificationCollectorService.clearKey()

        // Decryption with new key should fail to restore original plaintext encrypted with old key
        val decryptedAfter = NotificationCollectorService.decryptPayload(encryptedTitle)
        assertNotEquals(secretTitle, decryptedAfter)
    }

    @Test
    fun testEmptyAndInvalidPayloadsHandledGracefully() {
        assertEquals("", NotificationCollectorService.encryptPayload(""))
        assertEquals("", NotificationCollectorService.decryptPayload(""))
        assertEquals("", NotificationCollectorService.decryptPayload("invalid_base64_data"))
    }
}
