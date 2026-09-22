package com.scope.attentions

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.lang.reflect.Field

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
        // Access static queue via reflection or helper if needed
        val queueField: Field = NotificationCollectorService::class.java.getDeclaredField("queue")
        queueField.isAccessible = true
        @Suppress("UNCHECKED_CAST")
        val queue = queueField.get(null) as java.util.concurrent.ConcurrentLinkedQueue<NotificationData>
        queue.add(data)
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
        injectNotification("n_1")
        injectNotification("n_2")
        injectNotification("n_3")

        assertEquals(3, NotificationCollectorService.peekQueueCount())
        assertEquals(3, NotificationCollectorService.peekQueueCount()) // Non-destructive
    }

    @Test
    fun testBatchCappedAtMax100() {
        for (i in 1..120) {
            injectNotification("n_$i", "com.test", "Title $i", "Content $i")
        }

        assertEquals(120, NotificationCollectorService.peekQueueCount())

        val batch = NotificationCollectorService.fetchPendingBatch()
        assertNotNull(batch)
        assertEquals(100, batch!!.notifications.size)
        assertEquals(20, NotificationCollectorService.peekQueueCount())
    }

    @Test
    fun testUnacknowledgedBatchRollbackOnTimeout() {
        injectNotification("n_1", "com.test", "Unacknowledged", "Alert")

        val batch = NotificationCollectorService.fetchPendingBatch()
        assertNotNull(batch)
        assertEquals(0, NotificationCollectorService.peekQueueCount())

        // Simulate 30 second timeout by updating timestamp in pendingBatches
        val pendingBatchesField = NotificationCollectorService::class.java.getDeclaredField("pendingBatches")
        pendingBatchesField.isAccessible = true
        @Suppress("UNCHECKED_CAST")
        val pendingBatches = pendingBatchesField.get(null) as java.util.concurrent.ConcurrentHashMap<String, NotificationBatch>

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
