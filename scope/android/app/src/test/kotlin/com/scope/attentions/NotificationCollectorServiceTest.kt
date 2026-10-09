package com.scope.attentions

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.resetForTest()
    }

    @After
    fun tearDown() {
        NotificationCollectorService.resetForTest()
    }

    @Test
    fun testQueueCapacityLimit() {
        val now = 1_000_000_000L
        NotificationCollectorService.setMaxQueueCapacity(NotificationCollectorService.MAX_QUEUE_SIZE)

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
    fun testEnqueueSingleNotification() {
        val enqueued = NotificationCollectorService.enqueueNotification(
            packageName = "com.whatsapp",
            title = "Alice",
            content = "Hello world"
        )

        assertTrue("First notification should be enqueued successfully", enqueued)
        assertEquals(1, NotificationCollectorService.queueSize())

        val telemetry = NotificationCollectorService.getTelemetry()
        assertEquals(1L, telemetry["totalCapturedCount"])
        assertEquals(0L, telemetry["duplicateDroppedCount"])
        assertEquals(0L, telemetry["overflowEvictedCount"])
        assertEquals(1, telemetry["currentQueueSize"])
    }

    @Test
    fun testO1DuplicateDetection() {
        // Enqueue first notification
        val firstAdded = NotificationCollectorService.enqueueNotification(
            packageName = "com.whatsapp",
            title = "Alice",
            content = "Hello world"
        )
        assertTrue("First notification should be added", firstAdded)

        // Attempt duplicate notification with identical pkg, title, content
        val duplicateAdded = NotificationCollectorService.enqueueNotification(
            packageName = "com.whatsapp",
            title = "Alice",
            content = "Hello world"
        )
        assertFalse("Duplicate notification should be rejected", duplicateAdded)

        assertEquals(1, NotificationCollectorService.queueSize(), "Queue size should remain 1")

        val telemetry = NotificationCollectorService.getTelemetry()
        assertEquals(1L, telemetry["totalCapturedCount"])
        assertEquals(1L, telemetry["duplicateDroppedCount"])
    }

    @Test
    fun testQueueCapacityLimitAndEviction() {
        // Set capacity limit to 5
        NotificationCollectorService.setMaxQueueCapacity(5)

        // Enqueue 10 unique notifications
        for (i in 1..10) {
            val added = NotificationCollectorService.enqueueNotification(
                packageName = "com.example.app",
                title = "Title $i",
                content = "Content $i"
            )
            assertTrue("Notification $i should be added", added)
        }

        // Queue size should be capped at 5
        assertEquals(5, NotificationCollectorService.queueSize())

        val telemetry = NotificationCollectorService.getTelemetry()
        assertEquals(10L, telemetry["totalCapturedCount"])
        assertEquals(5L, telemetry["overflowEvictedCount"])
        assertEquals(5, telemetry["currentQueueSize"])

        // Drain queue and verify FIFO eviction: items 6 to 10 should be present
        val drained = NotificationCollectorService.drainQueue()
        assertEquals(5, drained.size)
        assertEquals("Title 6", drained[0].title)
        assertEquals("Title 10", drained[4].title)
    }

    @Test
    fun testDrainQueueClearsQueueAndSet() {
        NotificationCollectorService.enqueueNotification(
            packageName = "com.whatsapp",
            title = "Bob",
            content = "Meeting now"
        )

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(1, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())

        // Since queue was drained, adding the same notification again should succeed
        val reAdded = NotificationCollectorService.enqueueNotification(
            packageName = "com.whatsapp",
            title = "Bob",
            content = "Meeting now"
        )
        assertTrue("Re-adding notification after drain should succeed", reAdded)
    }

    @Test
    fun testPerformanceAndNoMemoryLeakUnderLoad() {
        val maxCap = 200
        NotificationCollectorService.setMaxQueueCapacity(maxCap)

        val startTime = System.currentTimeMillis()
        val totalCount = 10000

        for (i in 1..totalCount) {
            NotificationCollectorService.enqueueNotification(
                packageName = "com.app.${i % 50}",
                title = "Notification Title $i",
                content = "Notification Content Body $i"
            )
        }

        val duration = System.currentTimeMillis() - startTime
        println("Enqueued $totalCount notifications in $duration ms")

        // Queue must remain bounded at maxCap
        assertEquals(maxCap, NotificationCollectorService.queueSize())

        val telemetry = NotificationCollectorService.getTelemetry()
        assertEquals(totalCount.toLong(), telemetry["totalCapturedCount"])
        assertEquals((totalCount - maxCap).toLong(), telemetry["overflowEvictedCount"])

        // Performance check: 10,000 insertions with O(1) duplicate checks must execute rapidly (< 2000 ms)
        assertTrue("10,000 enqueues took $duration ms, expected < 2000ms", duration < 2000)
    }
}
