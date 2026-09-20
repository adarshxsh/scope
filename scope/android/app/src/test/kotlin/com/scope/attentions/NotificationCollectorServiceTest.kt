package com.scope.attentions

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.clearQueue()
    }

    @Test
    fun testGetBatchAndRetentionWithoutAck() {
        val notif1 = NotificationData("n1", "com.app1", "Title 1", "Body 1", 1000L, null, false)
        val notif2 = NotificationData("n2", "com.app2", "Title 2", "Body 2", 2000L, null, false)
        NotificationCollectorService.enqueueForTesting(notif1)
        NotificationCollectorService.enqueueForTesting(notif2)

        val now = System.currentTimeMillis()
        val batch1 = NotificationCollectorService.getBatch(currentTime = now)
        assertNotNull(batch1)
        assertTrue(batch1.batchId.isNotEmpty())
        assertEquals(2, batch1.notifications.size)

        // Multiple getBatch calls without acknowledgement re-deliver the active in-flight batch
        val batch2 = NotificationCollectorService.getBatch(currentTime = now + 1000)
        assertEquals(batch1.batchId, batch2.batchId)
        assertEquals(2, batch2.notifications.size)
    }

    @Test
    fun testAcknowledgeBatchRemovesFromMemory() {
        val notif = NotificationData("n1", "com.app1", "Title 1", "Body 1", 1000L, null, false)
        NotificationCollectorService.enqueueForTesting(notif)

        val now = System.currentTimeMillis()
        val batch = NotificationCollectorService.getBatch(currentTime = now)
        assertTrue(batch.batchId.isNotEmpty())

        val ackResult = NotificationCollectorService.acknowledgeBatch(batch.batchId)
        assertTrue(ackResult)

        // After acknowledgement, next batch is empty
        val nextBatch = NotificationCollectorService.getBatch(currentTime = now + 1000)
        assertTrue(nextBatch.batchId.isEmpty())
        assertTrue(nextBatch.notifications.isEmpty())
    }

    @Test
    fun testBatchTimeoutReleasesNotificationsToPendingQueue() {
        val notif = NotificationData("n1", "com.app1", "Title 1", "Body 1", 1000L, null, false)
        NotificationCollectorService.enqueueForTesting(notif)

        val startTime = 1000000L
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
        val notif1 = NotificationData("n1", "com.app1", "Title 1", "Body 1", 1000L, null, false)
        val notif2 = NotificationData("n2", "com.app2", "Title 2", "Body 2", 2000L, null, false)
        NotificationCollectorService.enqueueForTesting(notif1)
        NotificationCollectorService.enqueueForTesting(notif2)

        assertEquals(2, NotificationCollectorService.queueSize())

        val peeked = NotificationCollectorService.peekQueue()
        assertEquals(2, peeked.size)
        assertEquals(2, NotificationCollectorService.queueSize())

        // Fetching batch moves them to in-flight
        val batch = NotificationCollectorService.getBatch()
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
