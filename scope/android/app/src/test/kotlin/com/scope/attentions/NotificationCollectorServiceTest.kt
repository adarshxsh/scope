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
    fun testQueueCapacityLimit() {
        val now = 1_000_000_000L
        val maxCap = NotificationCollectorService.MAX_QUEUE_SIZE

        // Add MAX_QUEUE_SIZE notifications
        for (i in 1..maxCap) {
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

        assertEquals(maxCap, NotificationCollectorService.queueSize())

        // Add 101st notification
        val extraData = NotificationData(
            id = "notif_extra",
            packageName = "com.app.extra",
            title = "Title Extra",
            content = "Content Extra",
            timestamp = now,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(extraData, now)

        // Queue size should still be capped at MAX_QUEUE_SIZE
        assertEquals(maxCap, NotificationCollectorService.queueSize())

        // Drain queue and check contents
        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(maxCap, drained.size)

        // First item (com.app.1) should have been evicted (FIFO)
        assertFalse(drained.any { it.packageName == "com.app.1" })
        // Second item (com.app.2) and last item (com.app.extra) should be present
        assertTrue(drained.any { it.packageName == "com.app.2" })
        assertTrue(drained.any { it.packageName == "com.app.extra" })
    }

    @Test
    fun testQueueCapacityBoundAndDropOldestEviction() {
        val maxCap = NotificationCollectorService.MAX_QUEUE_SIZE
        val totalToPush = maxCap + 50
        val now = System.currentTimeMillis()

        for (i in 1..totalToPush) {
            val added = NotificationCollectorService.enqueueNotification(
                packageName = "com.example.app$i",
                title = "Title $i",
                content = "Content $i",
                timestamp = now + i,
                category = "msg",
                isOngoing = false
            )
            assertTrue("Expected notification $i to be added", added)
        }

        assertEquals(maxCap, NotificationCollectorService.queueSize())

        val notifications = NotificationCollectorService.drainQueue(now + totalToPush + 10)
        assertEquals(maxCap, notifications.size)

        // Oldest 50 items should have been evicted
        assertEquals("notif_51", notifications.first().id)
        assertEquals("notif_$totalToPush", notifications.last().id)
        assertEquals(0, NotificationCollectorService.queueSize())
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

        // Place fresh item
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

        // Drain at time postTime + MAX_AGE_MS + 10,000ms
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
    fun testDeduplicationAndDedupSetEviction() {
        val maxCap = NotificationCollectorService.MAX_QUEUE_SIZE

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

        // Push different items to trigger drop-oldest eviction of the initial notification
        for (i in 1..maxCap) {
            NotificationCollectorService.enqueueNotification(
                packageName = "com.example.filler",
                title = "Filler $i",
                content = "Filler content $i",
                timestamp = 2000L + i,
                category = "msg",
                isOngoing = false
            )
        }
        assertEquals(maxCap, NotificationCollectorService.queueSize())

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
        val maxCap = NotificationCollectorService.MAX_QUEUE_SIZE
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

        // Total pushed was 500, queue size should be capped at maxCap
        assertEquals(maxCap, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(maxCap, drained.size)

        // Ensure all generated IDs are distinct
        val uniqueIds = drained.map { it.id }.toSet()
        assertEquals(maxCap, uniqueIds.size)
    }

    @Test
    fun testDrainQueueClearsState() {
        val now = System.currentTimeMillis()
        for (i in 1..5) {
            NotificationCollectorService.enqueueNotification(
                packageName = "com.example.app",
                title = "Item $i",
                content = "Content $i",
                timestamp = now + i,
                category = null,
                isOngoing = false
            )
        }
        assertEquals(5, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue(now + 10)
        assertEquals(5, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())

        val drainedAgain = NotificationCollectorService.drainQueue(now + 10)
        assertTrue(drainedAgain.isEmpty())
    }
}
