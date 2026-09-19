package com.scope.attentions

import org.junit.After
import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

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
    fun testEnqueueSingleNotification() {
        val enqueued = NotificationCollectorService.enqueueNotification(
            packageName = "com.whatsapp",
            title = "Alice",
            content = "Hello world"
        )

        assertTrue(enqueued, "First notification should be enqueued successfully")
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
        assertTrue(firstAdded)

        // Attempt duplicate notification with identical pkg, title, content
        val duplicateAdded = NotificationCollectorService.enqueueNotification(
            packageName = "com.whatsapp",
            title = "Alice",
            content = "Hello world"
        )
        assertFalse(duplicateAdded, "Duplicate notification should be rejected")

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
            assertTrue(added)
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
        assertTrue(reAdded, "Re-adding notification after drain should succeed")
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
        assertTrue(duration < 2000, "10,000 enqueues took $duration ms, expected < 2000ms")
    }
}
