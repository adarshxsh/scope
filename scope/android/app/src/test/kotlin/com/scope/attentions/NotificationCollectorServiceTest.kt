package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors

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
    fun testCompositeKeyFormat() {
        val key = NotificationCollectorService.getCompositeKey("com.whatsapp", "Hello", "World")
        assertEquals("com.whatsapp|Hello|World", key)
    }

    @Test
    fun testDeduplicationRejectsDuplicates() {
        val addedFirst = NotificationCollectorService.addNotification("com.whatsapp", "Msg", "Hello")
        assertTrue(addedFirst)
        assertEquals(1, NotificationCollectorService.queueSize())

        // Duplicate addition should return false and not increment queue size
        val addedSecond = NotificationCollectorService.addNotification("com.whatsapp", "Msg", "Hello")
        assertFalse(addedSecond)
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testQueueCappedAt100Entries() {
        // Push 150 unique notifications
        for (i in 1..150) {
            val added = NotificationCollectorService.addNotification("com.app.$i", "Title $i", "Content $i")
            assertTrue(added)
        }

        // Queue size must strictly be capped at 100
        assertEquals(100, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(100, drained.size)

        // Verify that the oldest 50 items (1..50) were evicted, and items 51..150 remain
        assertEquals("com.app.51", drained.first().packageName)
        assertEquals("com.app.150", drained.last().packageName)
    }

    @Test
    fun testDrainQueueEmptiesQueueAndResetsSet() {
        NotificationCollectorService.addNotification("com.app.a", "Title A", "Content A")
        NotificationCollectorService.addNotification("com.app.b", "Title B", "Content B")
        assertEquals(2, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(2, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())

        // Re-adding same item after drain should succeed since set was cleared
        val addedAfterDrain = NotificationCollectorService.addNotification("com.app.a", "Title A", "Content A")
        assertTrue(addedAfterDrain)
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testDeduplicationLatencyUnderThreshold() {
        // Seed queue with 99 items
        for (i in 1..99) {
            NotificationCollectorService.addNotification("com.app.$i", "Title $i", "Content $i")
        }

        // Measure duplicate check time (should be O(1) < 0.1 ms)
        val startTime = System.nanoTime()
        val isAdded = NotificationCollectorService.addNotification("com.app.1", "Title 1", "Content 1")
        val elapsedTimeNs = System.nanoTime() - startTime
        val elapsedTimeMs = elapsedTimeNs / 1_000_000.0

        assertFalse(isAdded)
        assertTrue("Latency should be under 0.1ms, actual: ${elapsedTimeMs}ms", elapsedTimeMs < 0.1)
    }

    @Test
    fun testConcurrentAdditionsAreThreadSafe() {
        val threadCount = 10
        val itemsPerThread = 20
        val executor = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)

        for (t in 0 until threadCount) {
            executor.submit {
                try {
                    for (i in 0 until itemsPerThread) {
                        NotificationCollectorService.addNotification("com.app.t$t", "Title $i", "Content $i")
                    }
                } finally {
                    latch.countDown()
                }
            }
        }

        latch.await()
        executor.shutdown()

        // Total unique items = 10 * 20 = 200 items. Queue must cap at 100.
        assertEquals(100, NotificationCollectorService.queueSize())
    }
}
