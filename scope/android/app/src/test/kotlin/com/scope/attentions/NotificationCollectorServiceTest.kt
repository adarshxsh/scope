package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.clearQueue()
    }

    @Test
    fun testQueueCapacityLimit() {
        val now = 1_000_000_000L

        // Add MAX_QUEUE_SIZE (500) notifications
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
            val added = NotificationCollectorService.addNotification(data, now)
            assertTrue(added)
        }

        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize())
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.deduplicationSetSize())

        // Add 501st notification
        val extraData = NotificationData(
            id = "notif_501",
            packageName = "com.app.501",
            title = "Title 501",
            content = "Content 501",
            timestamp = now,
            category = null,
            isOngoing = false
        )
        val addedExtra = NotificationCollectorService.addNotification(extraData, now)
        assertTrue(addedExtra)

        // Queue size should still be capped at MAX_QUEUE_SIZE (500)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize())

        // Drain queue and check contents
        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, drained.size)

        // First item (com.app.1) should have been evicted (FIFO)
        assertFalse(drained.any { it.packageName == "com.app.1" })
        // Second item (com.app.2) and last item (com.app.501) should be present
        assertTrue(drained.any { it.packageName == "com.app.2" })
        assertTrue(drained.any { it.packageName == "com.app.501" })
    }

    @Test
    fun testQueueCapacityCeilingAndFifoEviction() {
        val baseTime = 1_000_000_000L
        // Add 550 notifications
        for (i in 1..550) {
            val added = NotificationCollectorService.addNotification(
                packageName = "com.test.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = baseTime + i
            )
            assertTrue("Failed to add item $i", added)
        }

        // Hard ceiling check
        val currentSize = NotificationCollectorService.queueSize()
        assertEquals(500, currentSize)
        assertEquals(500, NotificationCollectorService.deduplicationSetSize())

        // Check FIFO eviction: the first 50 items (1..50) should have been evicted
        val items = NotificationCollectorService.drainQueue(baseTime + 550)
        assertEquals(500, items.size)
        assertEquals("Title 51", items.first().title)
        assertEquals("Title 550", items.last().title)
    }

    @Test
    fun testAtomicIdGenerationAndUniquenessUnderConcurrency() {
        val threadCount = 10
        val itemsPerThread = 50
        val executor = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)
        val baseTime = System.currentTimeMillis()

        for (t in 0 until threadCount) {
            executor.submit {
                try {
                    for (i in 0 until itemsPerThread) {
                        NotificationCollectorService.addNotification(
                            packageName = "com.concurrent.app$t",
                            title = "Title $i from thread $t",
                            content = "Content $i",
                            timestamp = baseTime
                        )
                    }
                } finally {
                    latch.countDown()
                }
            }
        }

        val completed = latch.await(10, TimeUnit.SECONDS)
        executor.shutdown()
        assertTrue("Concurrent test timed out", completed)

        val items = NotificationCollectorService.drainQueue(baseTime)
        val totalExpected = threadCount * itemsPerThread
        assertEquals(totalExpected, items.size)

        val ids = items.map { it.id }.toSet()
        assertEquals(totalExpected, ids.size)
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
        val addedExpired = NotificationCollectorService.addNotification(expiredData, baseTime)
        assertFalse(addedExpired)

        // Since pruneExpired runs on addNotification, adding an expired item relative to baseTime should not remain
        assertEquals(0, NotificationCollectorService.queueSize())

        // Add fresh item
        val freshData = NotificationData(
            id = "fresh_1",
            packageName = "com.app.fresh",
            title = "Fresh Title",
            content = "Fresh Content",
            timestamp = baseTime,
            category = null,
            isOngoing = false
        )
        val addedFresh = NotificationCollectorService.addNotification(freshData, baseTime)
        assertTrue(addedFresh)

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
        val addedNewer = NotificationCollectorService.addNotification(newerData, futureTime)
        assertTrue(addedNewer)

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
        val added1 = NotificationCollectorService.addNotification(notif1, t0)
        assertTrue(added1)

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
        val addedDup = NotificationCollectorService.addNotification(dupNotif, t0)
        assertFalse(addedDup)
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
        val addedNew = NotificationCollectorService.addNotification(newNotif, tFuture)
        assertTrue(addedNew)

        assertEquals(1, NotificationCollectorService.queueSize())
        val drained = NotificationCollectorService.drainQueue(tFuture)
        assertEquals(1, drained.size)
        assertEquals("3", drained[0].id)
    }

    @Test
    fun testDeduplicationRejection() {
        val baseTime = 1_000_000_000L
        val addedFirst = NotificationCollectorService.addNotification(
            packageName = "com.example.chat",
            title = "Alice",
            content = "Hello there",
            timestamp = baseTime
        )
        assertTrue("First notification should be added", addedFirst)

        val addedDuplicate = NotificationCollectorService.addNotification(
            packageName = "com.example.chat",
            title = "Alice",
            content = "Hello there",
            timestamp = baseTime + 1000L
        )
        assertFalse("Duplicate notification should be rejected", addedDuplicate)

        assertEquals(1, NotificationCollectorService.queueSize())
        assertEquals(1, NotificationCollectorService.deduplicationSetSize())
    }

    @Test
    fun testDrainQueuePurgesQueueAndDeduplicationSet() {
        val baseTime = 1_000_000_000L
        for (i in 1..10) {
            NotificationCollectorService.addNotification(
                packageName = "com.test.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = baseTime + i
            )
        }

        assertEquals(10, NotificationCollectorService.queueSize())
        assertEquals(10, NotificationCollectorService.deduplicationSetSize())

        val drained = NotificationCollectorService.drainQueue(baseTime + 10)
        assertEquals(10, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())
        assertEquals(0, NotificationCollectorService.deduplicationSetSize())
    }
}
