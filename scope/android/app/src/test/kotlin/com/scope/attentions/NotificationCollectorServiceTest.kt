package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
    fun testPeekQueueIsNonDestructive() {
        val now = System.currentTimeMillis()
        val notif1 = NotificationData("n1", "com.test", "Title 1", "Body 1", now)
        val notif2 = NotificationData("n2", "com.test", "Title 2", "Body 2", now + 1000L)

        NotificationCollectorService.addNotificationForTest(notif1, now)
        NotificationCollectorService.addNotificationForTest(notif2, now + 1000L)

        assertEquals(2, NotificationCollectorService.queueSize())

        val peeked = NotificationCollectorService.peekQueue(now + 1000L)
        assertEquals(2, peeked.size)
        assertEquals("n1", peeked[0].id)
        assertEquals("n2", peeked[1].id)

        // Queue size remains 2 after peeking
        assertEquals(2, NotificationCollectorService.queueSize())
    }

    @Test
    fun testAcknowledgeRemovesOnlySpecifiedIds() {
        val now = System.currentTimeMillis()
        val notif1 = NotificationData("n1", "com.test", "Title 1", "Body 1", now)
        val notif2 = NotificationData("n2", "com.test", "Title 2", "Body 2", now + 1000L)
        val notif3 = NotificationData("n3", "com.test", "Title 3", "Body 3", now + 2000L)

        NotificationCollectorService.addNotificationForTest(notif1, now)
        NotificationCollectorService.addNotificationForTest(notif2, now + 1000L)
        NotificationCollectorService.addNotificationForTest(notif3, now + 2000L)

        assertEquals(3, NotificationCollectorService.queueSize())

        val ackedCount = NotificationCollectorService.acknowledge(listOf("n1", "n3"))
        assertEquals(2, ackedCount)

        assertEquals(1, NotificationCollectorService.queueSize())
        val remaining = NotificationCollectorService.peekQueue(now + 2000L)
        assertEquals("n2", remaining[0].id)
    }

    @Test
    fun testMaxQueueCapacityEnforcement() {
        val now = System.currentTimeMillis()
        NotificationCollectorService.maxQueueCapacity = 3

        val notif1 = NotificationData("n1", "com.test", "Title 1", "Body 1", now)
        val notif2 = NotificationData("n2", "com.test", "Title 2", "Body 2", now + 1000L)
        val notif3 = NotificationData("n3", "com.test", "Title 3", "Body 3", now + 2000L)
        val notif4 = NotificationData("n4", "com.test", "Title 4", "Body 4", now + 3000L)

        NotificationCollectorService.addNotificationForTest(notif1, now)
        NotificationCollectorService.addNotificationForTest(notif2, now + 1000L)
        NotificationCollectorService.addNotificationForTest(notif3, now + 2000L)
        assertEquals(3, NotificationCollectorService.queueSize())

        // Adding 4th item when max capacity is 3 should evict the oldest item (n1)
        NotificationCollectorService.addNotificationForTest(notif4, now + 3000L)
        assertEquals(3, NotificationCollectorService.queueSize())

        val remaining = NotificationCollectorService.peekQueue(now + 3000L)
        assertEquals(listOf("n2", "n3", "n4"), remaining.map { it.id })
    }

    @Test
    fun testAcknowledgeWithEmptyListDoesNothing() {
        val now = System.currentTimeMillis()
        val notif1 = NotificationData("n1", "com.test", "Title 1", "Body 1", now)
        NotificationCollectorService.addNotificationForTest(notif1, now)

        val ackedCount = NotificationCollectorService.acknowledge(emptyList())
        assertEquals(0, ackedCount)
        assertEquals(1, NotificationCollectorService.queueSize())
    }
}
