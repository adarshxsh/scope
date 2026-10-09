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
        NotificationCollectorService.resetForTesting()
    }

    @Test
    fun testQueueBoundedAt250AndEvictsOldest() {
        val now = 10_000L
        // Fill queue to capacity (250)
        for (i in 0 until 250) {
            val added = NotificationCollectorService.enqueueNotification(
                packageName = "com.test.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = now,
                category = "msg",
                isOngoing = false,
                now = now
            )
            assertTrue("Expected item $i to be added", added)
        }

        assertEquals(250, NotificationCollectorService.queueSize())

        // Add 251st item which should trigger drop-oldest eviction
        val addedOverflow = NotificationCollectorService.enqueueNotification(
            packageName = "com.test.app",
            title = "Title 250",
            content = "Content 250",
            timestamp = now,
            category = "msg",
            isOngoing = false,
            now = now
        )
        assertTrue("Expected 251st item to be added", addedOverflow)

        // Queue size remains capped at 250
        assertEquals(250, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(250, drained.size)

        // First item should now be "Title 1" (Title 0 was evicted)
        assertEquals("Title 1", drained.first().title)
        assertEquals("notif_2", drained.first().id)

        // Last item should be "Title 250"
        assertEquals("Title 250", drained.last().title)
        assertEquals("notif_251", drained.last().id)
    }

    @Test
    fun testQueueCapacityLimitWithAddNotification() {
        val now = 1_000_000_000L

        // Add MAX_QUEUE_SIZE (250) notifications
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

        // Add 251st notification
        val extraData = NotificationData(
            id = "notif_251",
            packageName = "com.app.251",
            title = "Title 251",
            content = "Content 251",
            timestamp = now,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(extraData, now)

        // Queue size should still be capped at MAX_QUEUE_SIZE (250)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize())

        // Drain queue and check contents
        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, drained.size)

        // First item (com.app.1) should have been evicted (FIFO)
        assertFalse(drained.any { it.packageName == "com.app.1" })
        // Second item (com.app.2) and last item (com.app.251) should be present
        assertTrue(drained.any { it.packageName == "com.app.2" })
        assertTrue(drained.any { it.packageName == "com.app.251" })
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

        // Manually place item with fresh timestamp
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
        assertEquals("notif_2", drained[0].id)
    }

    @Test
    fun testO1Deduplication() {
        val now = 10_000L
        val addedFirst = NotificationCollectorService.enqueueNotification(
            packageName = "com.test.chat",
            title = "Alice",
            content = "Hello world",
            timestamp = now,
            category = "msg",
            isOngoing = false,
            now = now
        )
        assertTrue(addedFirst)

        // Attempt duplicate notification
        val addedDuplicate = NotificationCollectorService.enqueueNotification(
            packageName = "com.test.chat",
            title = "Alice",
            content = "Hello world",
            timestamp = now + 5,
            category = "msg",
            isOngoing = false,
            now = now + 5
        )
        assertFalse("Duplicate notification should be rejected", addedDuplicate)

        assertEquals(1, NotificationCollectorService.queueSize())

        // Non-duplicate with different content should succeed
        val addedNew = NotificationCollectorService.enqueueNotification(
            packageName = "com.test.chat",
            title = "Alice",
            content = "How are you?",
            timestamp = now + 10,
            category = "msg",
            isOngoing = false,
            now = now + 10
        )
        assertTrue(addedNew)
        assertEquals(2, NotificationCollectorService.queueSize())
    }

    @Test
    fun testDrainQueueEmptiesQueueAndClearsDeduplicationSet() {
        val now = 10_000L
        NotificationCollectorService.enqueueNotification(
            packageName = "com.test.email",
            title = "Newsletter",
            content = "Weekly digest",
            timestamp = now,
            category = "promo",
            isOngoing = false,
            now = now
        )

        assertEquals(1, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(1, drained.size)
        assertEquals("Newsletter", drained[0].title)

        // Queue is empty
        assertEquals(0, NotificationCollectorService.queueSize())

        // Re-adding same notification after drain should succeed
        val addedAfterDrain = NotificationCollectorService.enqueueNotification(
            packageName = "com.test.email",
            title = "Newsletter",
            content = "Weekly digest",
            timestamp = now + 1000,
            category = "promo",
            isOngoing = false,
            now = now + 1000
        )
        assertTrue("Should allow re-enqueue after queue drain", addedAfterDrain)
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testEvictionRemovesKeyFromDeduplicationSet() {
        val now = 10_000L
        // Fill queue with 250 items
        for (i in 0 until 250) {
            NotificationCollectorService.enqueueNotification(
                packageName = "com.test.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = now,
                category = "sys",
                isOngoing = false,
                now = now
            )
        }

        // Add 251st item, evicting "Title 0"
        NotificationCollectorService.enqueueNotification(
            packageName = "com.test.app",
            title = "Title 250",
            content = "Content 250",
            timestamp = now,
            category = "sys",
            isOngoing = false,
            now = now
        )

        // Re-add "Title 0" which was evicted; it should succeed
        val readdedEvicted = NotificationCollectorService.enqueueNotification(
            packageName = "com.test.app",
            title = "Title 0",
            content = "Content 0",
            timestamp = now,
            category = "sys",
            isOngoing = false,
            now = now
        )
        assertTrue("Evicted notification key should be removed from dedup set", readdedEvicted)
    }

    @Test
    fun testThreadSafeAtomicCounterAndConcurrentEnqueue() {
        val threadCount = 10
        val itemsPerThread = 100
        val totalItems = threadCount * itemsPerThread

        val executor = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)

        val now = System.currentTimeMillis()

        for (t in 0 until threadCount) {
            executor.execute {
                try {
                    for (i in 0 until itemsPerThread) {
                        NotificationCollectorService.enqueueNotification(
                            packageName = "com.test.thread$t",
                            title = "Title $i",
                            content = "Content $i",
                            timestamp = now,
                            category = "sys",
                            isOngoing = false,
                            now = now
                        )
                    }
                } finally {
                    latch.countDown()
                }
            }
        }

        latch.await()
        executor.shutdown()

        // 1000 unique items enqueued total; queue is bounded at 250
        assertEquals(250, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(250, drained.size)

        // All drained IDs should be unique
        val uniqueIds = drained.map { it.id }.toSet()
        assertEquals(250, uniqueIds.size)

        // All IDs must follow "notif_<number>" format with atomic numbers up to 1000
        for (item in drained) {
            assertTrue(item.id.startsWith("notif_"))
            val num = item.id.removePrefix("notif_").toLong()
            assertTrue("ID number $num should be between 1 and $totalItems", num in 1..totalItems)
        }
    }
}
