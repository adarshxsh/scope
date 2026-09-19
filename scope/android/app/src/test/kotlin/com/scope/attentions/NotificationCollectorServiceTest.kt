package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.clearQueue()
        NotificationCollectorService.resetIdCounter()
    }

    @Test
    fun testQueueCapacityBoundAndDropOldestEviction() {
        // Enqueue 300 notifications (exceeding MAX_QUEUE_SIZE of 250)
        for (i in 1..300) {
            val added = NotificationCollectorService.enqueueNotification(
                packageName = "com.example.app$i",
                title = "Title $i",
                content = "Content $i",
                timestamp = 1000L + i,
                category = "msg",
                isOngoing = false
            )
            assertTrue("Expected notification $i to be added", added)
        }

        // Queue size should be strictly bounded at MAX_QUEUE_SIZE (250)
        assertEquals(250, NotificationCollectorService.queueSize())

        val notifications = NotificationCollectorService.drainQueue()
        assertEquals(250, notifications.size)

        // Oldest 50 items (notif_1 .. notif_50) should have been evicted
        assertEquals("notif_51", notifications.first().id)
        assertEquals("notif_300", notifications.last().id)
        assertEquals(0, NotificationCollectorService.queueSize())
    }

    @Test
    fun testDeduplicationAndDedupSetEviction() {
        // Enqueue initial notification
        val added1 = NotificationCollectorService.enqueueNotification(
            packageName = "com.example.app",
            title = "Title A",
            content = "Content A",
            timestamp = 1000L,
            category = "msg",
            isOngoing = false
        )
        assertTrue(added1)
        assertEquals(1, NotificationCollectorService.queueSize())

        // Duplicate notification should be rejected
        val addedDuplicate = NotificationCollectorService.enqueueNotification(
            packageName = "com.example.app",
            title = "Title A",
            content = "Content A",
            timestamp = 1001L,
            category = "msg",
            isOngoing = false
        )
        assertFalse(addedDuplicate)
        assertEquals(1, NotificationCollectorService.queueSize())

        // Push 250 different items to trigger drop-oldest eviction of the initial notification
        for (i in 1..250) {
            NotificationCollectorService.enqueueNotification(
                packageName = "com.example.filler",
                title = "Filler $i",
                content = "Filler content $i",
                timestamp = 2000L + i,
                category = "msg",
                isOngoing = false
            )
        }
        assertEquals(250, NotificationCollectorService.queueSize())

        // Now re-enqueuing "Title A" should succeed because its dedup key was evicted with the dropped notification
        val reAdded = NotificationCollectorService.enqueueNotification(
            packageName = "com.example.app",
            title = "Title A",
            content = "Content A",
            timestamp = 3000L,
            category = "msg",
            isOngoing = false
        )
        assertTrue("Expected re-added notification to succeed after eviction", reAdded)

        NotificationCollectorService.clearQueue()
    }

    @Test
    fun testFilteringOngoingNotifications() {
        val added = NotificationCollectorService.enqueueNotification(
            packageName = "com.example.ongoing",
            title = "System Update",
            content = "Downloading...",
            timestamp = 1000L,
            category = "sys",
            isOngoing = true
        )
        assertFalse("Ongoing notifications must be filtered out", added)
        assertEquals(0, NotificationCollectorService.queueSize())
    }

    @Test
    fun testFilteringExcludedCategories() {
        val excluded = listOf("progress", "navigation", "service", "sys", "system", "transport", "status")
        for (cat in excluded) {
            val added = NotificationCollectorService.enqueueNotification(
                packageName = "com.example.service",
                title = "Status Title",
                content = "Status Text",
                timestamp = 1000L,
                category = cat.uppercase(),
                isOngoing = false
            )
            assertFalse("Category $cat should be excluded", added)
        }
        assertEquals(0, NotificationCollectorService.queueSize())

        // Allowed category should pass
        val allowedAdded = NotificationCollectorService.enqueueNotification(
            packageName = "com.example.allowed",
            title = "Normal Title",
            content = "Normal Content",
            timestamp = 1000L,
            category = "msg",
            isOngoing = false
        )
        assertTrue(allowedAdded)
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testAtomicLongAndConcurrentEnqueueing() {
        val numThreads = 10
        val itemsPerThread = 50
        val executor = Executors.newFixedThreadPool(numThreads)

        for (t in 0 until numThreads) {
            executor.submit {
                for (i in 0 until itemsPerThread) {
                    NotificationCollectorService.enqueueNotification(
                        packageName = "com.example.thread$t",
                        title = "Title $t-$i",
                        content = "Content $t-$i",
                        timestamp = System.currentTimeMillis(),
                        category = "msg",
                        isOngoing = false
                    )
                }
            }
        }

        executor.shutdown()
        assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS))

        // Total pushed was 500, queue size should be capped at 250
        assertEquals(250, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(250, drained.size)

        // Ensure all generated IDs are distinct (no race condition ID collisions)
        val uniqueIds = drained.map { it.id }.toSet()
        assertEquals(250, uniqueIds.size)
    }

    @Test
    fun testDrainQueueClearsState() {
        for (i in 1..5) {
            NotificationCollectorService.enqueueNotification(
                packageName = "com.example.app",
                title = "Item $i",
                content = "Content $i",
                timestamp = 1000L + i,
                category = null,
                isOngoing = false
            )
        }
        assertEquals(5, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(5, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())

        val drainedAgain = NotificationCollectorService.drainQueue()
        assertTrue(drainedAgain.isEmpty())
    }
}
