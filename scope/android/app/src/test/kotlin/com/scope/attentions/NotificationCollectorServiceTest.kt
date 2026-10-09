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
    fun testQueueCapacityLimit() {
        val now = 1_000_000_000L

        // Add MAX_QUEUE_SIZE (100) notifications
        for (i in 1..NotificationCollectorService.MAX_QUEUE_SIZE) {
            val data = NotificationData(
                id = "notif_$i",
                packageName = "com.app.$i",
                title = "Title $i",
                content = "Content $i",
                timestamp = now,
                category = null,
                isOngoing = false
            )
            NotificationCollectorService.addNotification(data, now)
        }

        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize())

        // Add 101st notification
        val extraData = NotificationData(
            id = "notif_101",
            packageName = "com.app.101",
            title = "Title 101",
            content = "Content 101",
            timestamp = now,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(extraData, now)

        // Queue size should still be capped at MAX_QUEUE_SIZE (100)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize())

        // Drain queue and check contents
        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, drained.size)

        // First item (com.app.1) should have been evicted (FIFO)
        assertFalse(drained.any { it.packageName == "com.app.1" })
        // Second item (com.app.2) and last item (com.app.101) should be present
        assertTrue(drained.any { it.packageName == "com.app.2" })
        assertTrue(drained.any { it.packageName == "com.app.101" })
    }

    @Test
    fun testTtlEvictionDuringCapture() {
        val baseTime = 1_000_000_000L
        val expiredTime = baseTime - (NotificationCollectorService.MAX_AGE_MS + 1000L)

        // Add an expired notification directly
        val expiredData = NotificationData(
            id = "old_1",
            packageName = "com.app.old",
            title = "Old Title",
            content = "Old Content",
            timestamp = expiredTime,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(expiredData, baseTime)

        // Since pruneExpired runs on addNotification, adding an expired item relative to baseTime should not remain
        assertEquals(0, NotificationCollectorService.queueSize())

        // Manually place fresh item
        val freshData = NotificationData(
            id = "fresh_1",
            packageName = "com.app.fresh",
            title = "Fresh Title",
            content = "Fresh Content",
            timestamp = baseTime,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(freshData, baseTime)

        assertEquals(1, NotificationCollectorService.queueSize())

        // Now add another item at baseTime + MAX_AGE_MS + 2000L (so fresh_1 expires)
        val futureTime = baseTime + NotificationCollectorService.MAX_AGE_MS + 2000L
        val newerData = NotificationData(
            id = "newer_1",
            packageName = "com.app.newer",
            title = "Newer Title",
            content = "Newer Content",
            timestamp = futureTime,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(newerData, futureTime)

        // fresh_1 should be evicted during pruneExpired on capture
        assertEquals(1, NotificationCollectorService.queueSize())
        val drained = NotificationCollectorService.drainQueue(futureTime)
        assertEquals(1, drained.size)
        assertEquals("com.app.newer", drained[0].packageName)
    }

    @Test
    fun testTtlEvictionDuringDrain() {
        val postTime = 1_000_000_000L

        val notif = NotificationData(
            id = "n1",
            packageName = "com.app.test",
            title = "Title",
            content = "Content",
            timestamp = postTime,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(notif, postTime)
        assertEquals(1, NotificationCollectorService.queueSize())

        // Drain at time postTime + MAX_AGE_MS + 10,000ms (15m10s later)
        val drainTime = postTime + NotificationCollectorService.MAX_AGE_MS + 10_000L
        val drained = NotificationCollectorService.drainQueue(drainTime)

        assertTrue("Expired item should be filtered out on drain", drained.isEmpty())
        assertEquals(0, NotificationCollectorService.queueSize())
    }

    @Test
    fun testDuplicateHandlingAndResubmissionAfterExpiry() {
        val t0 = 1_000_000_000L

        val notif1 = NotificationData(
            id = "1",
            packageName = "com.app.chat",
            title = "Hello",
            content = "World",
            timestamp = t0,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(notif1, t0)

        // Attempting to add duplicate at t0 should be ignored
        val dupNotif = NotificationData(
            id = "2",
            packageName = "com.app.chat",
            title = "Hello",
            content = "World",
            timestamp = t0,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(dupNotif, t0)
        assertEquals(1, NotificationCollectorService.queueSize())

        // Advance time past expiry
        val tFuture = t0 + NotificationCollectorService.MAX_AGE_MS + 5000L

        // Adding same notification after expiry should prune old and succeed
        val newNotif = NotificationData(
            id = "3",
            packageName = "com.app.chat",
            title = "Hello",
            content = "World",
            timestamp = tFuture,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(newNotif, tFuture)

        assertEquals(1, NotificationCollectorService.queueSize())
        val drained = NotificationCollectorService.drainQueue(tFuture)
        assertEquals(1, drained.size)
        assertEquals("3", drained[0].id)
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
