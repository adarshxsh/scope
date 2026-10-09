package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.clearQueue()
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

        // Manually place old item with older timestamp and add fresh item
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
    fun testGetBatchAndRetentionWithoutAck() {
        val now = 1_000_000_000L
        val notif1 = NotificationData("n1", "com.app1", "Title 1", "Body 1", now, null, false)
        val notif2 = NotificationData("n2", "com.app2", "Title 2", "Body 2", now + 1000L, null, false)
        NotificationCollectorService.enqueueForTesting(notif1)
        NotificationCollectorService.enqueueForTesting(notif2)

        val batch1 = NotificationCollectorService.getBatch(currentTime = now + 1000L)
        assertNotNull(batch1)
        assertTrue(batch1.batchId.isNotEmpty())
        assertEquals(2, batch1.notifications.size)

        // Multiple getBatch calls without acknowledgement re-deliver the active in-flight batch
        val batch2 = NotificationCollectorService.getBatch(currentTime = now + 2000L)
        assertEquals(batch1.batchId, batch2.batchId)
        assertEquals(2, batch2.notifications.size)
    }

    @Test
    fun testAcknowledgeBatchRemovesFromMemory() {
        val now = 1_000_000_000L
        val notif = NotificationData("n1", "com.app1", "Title 1", "Body 1", now, null, false)
        NotificationCollectorService.enqueueForTesting(notif)

        val batch = NotificationCollectorService.getBatch(currentTime = now)
        assertTrue(batch.batchId.isNotEmpty())

        val ackResult = NotificationCollectorService.acknowledgeBatch(batch.batchId)
        assertTrue(ackResult)

        // After acknowledgement, next batch is empty
        val nextBatch = NotificationCollectorService.getBatch(currentTime = now + 1000L)
        assertTrue(nextBatch.batchId.isEmpty())
        assertTrue(nextBatch.notifications.isEmpty())
    }

    @Test
    fun testBatchTimeoutReleasesNotificationsToPendingQueue() {
        val startTime = 1_000_000_000L
        val notif = NotificationData("n1", "com.app1", "Title 1", "Body 1", startTime, null, false)
        NotificationCollectorService.enqueueForTesting(notif)

        val batch1 = NotificationCollectorService.getBatch(currentTime = startTime)
        assertEquals(1, batch1.notifications.size)
        val initialBatchId = batch1.batchId

        // Call getBatch after 5 minutes (300,000 ms + 1 ms)
        val timeoutTime = startTime + 300001L
        val batch2 = NotificationCollectorService.getBatch(currentTime = timeoutTime)

        assertNotNull(batch2)
        assertTrue(batch2.batchId.isNotEmpty())
        assertNotEquals(initialBatchId, batch2.batchId)
        assertEquals(1, batch2.notifications.size)
        assertEquals("n1", batch2.notifications[0].id)
    }

    @Test
    fun testNonDestructivePeekQueueAndGetQueueSize() {
        val now = 1_000_000_000L
        val notif1 = NotificationData("n1", "com.app1", "Title 1", "Body 1", now, null, false)
        val notif2 = NotificationData("n2", "com.app2", "Title 2", "Body 2", now + 1000L, null, false)
        NotificationCollectorService.enqueueForTesting(notif1)
        NotificationCollectorService.enqueueForTesting(notif2)

        assertEquals(2, NotificationCollectorService.queueSize())

        val peeked = NotificationCollectorService.peekQueue()
        assertEquals(2, peeked.size)
        assertEquals(2, NotificationCollectorService.queueSize())

        // Fetching batch moves them to in-flight
        val batch = NotificationCollectorService.getBatch(currentTime = now + 2000L)
        assertEquals(0, NotificationCollectorService.queueSize()) // pending queue is now 0
        assertEquals(2, batch.notifications.size)
    }

    @Test
    fun testAcknowledgeInvalidOrEmptyBatchIdReturnsFalse() {
        assertFalse(NotificationCollectorService.acknowledgeBatch(""))
        assertFalse(NotificationCollectorService.acknowledgeBatch(null))
        assertFalse(NotificationCollectorService.acknowledgeBatch("non_existent_batch_id"))
    }
}
