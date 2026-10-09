package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.ConcurrentHashMap

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.clearAll()
    }

    private fun injectNotification(
        id: String = "n_1",
        packageName: String = "com.example.app",
        title: String = "Test Title",
        content: String = "Test Body",
        timestamp: Long = System.currentTimeMillis()
    ) {
        val data = NotificationData(
            id = id,
            packageName = packageName,
            title = title,
            content = content,
            timestamp = timestamp,
            category = "msg",
            isOngoing = false
        )
        NotificationCollectorService.addNotification(data, timestamp)
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

        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize(now))

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
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize(now))

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
        assertEquals(0, NotificationCollectorService.queueSize(baseTime))

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

        assertEquals(1, NotificationCollectorService.queueSize(baseTime))

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
        assertEquals(1, NotificationCollectorService.queueSize(futureTime))
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
        assertEquals(1, NotificationCollectorService.queueSize(postTime))

        // Drain at time postTime + MAX_AGE_MS + 10,000ms (15m10s later)
        val drainTime = postTime + NotificationCollectorService.MAX_AGE_MS + 10_000L
        val drained = NotificationCollectorService.drainQueue(drainTime)

        assertTrue("Expired item should be filtered out on drain", drained.isEmpty())
        assertEquals(0, NotificationCollectorService.queueSize(drainTime))
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
        assertEquals(1, NotificationCollectorService.queueSize(t0))

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

        assertEquals(1, NotificationCollectorService.queueSize(tFuture))
        val drained = NotificationCollectorService.drainQueue(tFuture)
        assertEquals(1, drained.size)
        assertEquals("3", drained[0].id)
    }

    @Test
    fun testFetchPendingBatchAndAcknowledge() {
        injectNotification("n_1", "com.test", "Hello", "World")

        assertEquals(1, NotificationCollectorService.peekQueueCount())

        val batch = NotificationCollectorService.fetchPendingBatch()
        assertNotNull(batch)
        assertTrue(batch!!.batchId.startsWith("tx_"))
        assertEquals(1, batch.notifications.size)
        assertEquals("Hello", batch.notifications[0].title)

        // Queue size should be 0 because item moved to pending batch
        assertEquals(0, NotificationCollectorService.peekQueueCount())

        // Acknowledge batch
        val ackResult = NotificationCollectorService.acknowledgeBatch(batch.batchId)
        assertTrue(ackResult)

        // Second acknowledgement should return false
        val reAckResult = NotificationCollectorService.acknowledgeBatch(batch.batchId)
        assertFalse(reAckResult)
    }

    @Test
    fun testNonDestructivePeekQueueCount() {
        injectNotification("n_1", packageName = "com.test.1", title = "T1", content = "C1")
        injectNotification("n_2", packageName = "com.test.2", title = "T2", content = "C2")
        injectNotification("n_3", packageName = "com.test.3", title = "T3", content = "C3")

        assertEquals(3, NotificationCollectorService.peekQueueCount())
        assertEquals(3, NotificationCollectorService.peekQueueCount()) // Non-destructive
    }

    @Test
    fun testBatchCappedAtMax100() {
        for (i in 1..120) {
            injectNotification("n_$i", "com.test.$i", "Title $i", "Content $i")
        }

        assertEquals(100, NotificationCollectorService.peekQueueCount())

        val batch = NotificationCollectorService.fetchPendingBatch()
        assertNotNull(batch)
        assertEquals(100, batch!!.notifications.size)
        assertEquals(0, NotificationCollectorService.peekQueueCount())
    }

    @Test
    fun testUnacknowledgedBatchRollbackOnTimeout() {
        injectNotification("n_1", "com.test", "Unacknowledged", "Alert")

        val batch = NotificationCollectorService.fetchPendingBatch()
        assertNotNull(batch)
        assertEquals(0, NotificationCollectorService.peekQueueCount())

        // Simulate 30 second timeout by updating timestamp in pendingBatches via reflection
        val pendingBatchesField = NotificationCollectorService::class.java.getDeclaredField("pendingBatches")
        pendingBatchesField.isAccessible = true
        @Suppress("UNCHECKED_CAST")
        val pendingBatches = pendingBatchesField.get(null) as ConcurrentHashMap<String, NotificationBatch>

        val existingBatch = pendingBatches[batch!!.batchId]
        if (existingBatch != null) {
            val expiredBatch = NotificationBatch(
                batchId = existingBatch.batchId,
                notifications = existingBatch.notifications,
                timestamp = System.currentTimeMillis() - 35_000L // 35s ago
            )
            pendingBatches[batch.batchId] = expiredBatch
        }

        // Trigger rollback
        NotificationCollectorService.rollbackExpiredBatches()

        // Notification should be back in queue!
        assertEquals(1, NotificationCollectorService.peekQueueCount())

        // Re-fetching should succeed and yield the same notification
        val reFetchedBatch = NotificationCollectorService.fetchPendingBatch()
        assertNotNull(reFetchedBatch)
        assertEquals(1, reFetchedBatch!!.notifications.size)
        assertEquals("Unacknowledged", reFetchedBatch.notifications[0].title)
    }
}
