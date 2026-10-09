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
    fun testQueueBoundedAndEviction() {
        // Enqueue 150 unique notifications
        val now = 1_000_000_000L
        for (i in 1..150) {
            val added = NotificationCollectorService.addNotification(
                packageName = "com.example.app$i",
                title = "Title $i",
                content = "Content $i",
                timestamp = now,
                now = now
            )
            assertTrue("Item $i should be added", added)
            assertTrue(
                "Queue size should never exceed MAX_QUEUE_SIZE",
                NotificationCollectorService.queueSize() <= NotificationCollectorService.MAX_QUEUE_SIZE
            )
        }

        assertEquals(
            "Queue size should be capped at MAX_QUEUE_SIZE",
            NotificationCollectorService.MAX_QUEUE_SIZE,
            NotificationCollectorService.queueSize()
        )

        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, drained.size)

        // The oldest 50 items (1..50) should have been evicted.
        // So the first item in the drained queue should be item 51.
        assertEquals("com.example.app51", drained.first().packageName)
        assertEquals("Title 51", drained.first().title)
        assertEquals("com.example.app150", drained.last().packageName)
        assertEquals("Title 150", drained.last().title)

        // Verifying evicted deduplication keys:
        // Item 1 was evicted, so re-adding item 1 should now succeed
        val reAddedItem1 = NotificationCollectorService.addNotification(
            packageName = "com.example.app1",
            title = "Title 1",
            content = "Content 1",
            timestamp = now,
            now = now
        )
        assertTrue("Evicted key should be cleared from dedupSet allowing re-addition", reAddedItem1)
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testDeduplicationO1() {
        val now = 1_000_000_000L
        val addedFirst = NotificationCollectorService.addNotification(
            packageName = "com.test.app",
            title = "Alert",
            content = "Message Body",
            timestamp = now,
            now = now
        )
        assertTrue("First insertion should succeed", addedFirst)
        assertEquals(1, NotificationCollectorService.queueSize())

        // Duplicate insertion
        val addedDuplicate = NotificationCollectorService.addNotification(
            packageName = "com.test.app",
            title = "Alert",
            content = "Message Body",
            timestamp = now,
            now = now
        )
        assertFalse("Duplicate notification should be rejected", addedDuplicate)
        assertEquals(1, NotificationCollectorService.queueSize())

        // Different title -> non-duplicate
        val addedDifferentTitle = NotificationCollectorService.addNotification(
            packageName = "com.test.app",
            title = "Alert 2",
            content = "Message Body",
            timestamp = now,
            now = now
        )
        assertTrue("Different title notification should be accepted", addedDifferentTitle)
        assertEquals(2, NotificationCollectorService.queueSize())
    }

    @Test
    fun testDrainQueueClearsQueueAndDedupSet() {
        val now = 1_000_000_000L
        NotificationCollectorService.addNotification("com.app", "Title 1", "Body 1", timestamp = now, now = now)
        NotificationCollectorService.addNotification("com.app", "Title 2", "Body 2", timestamp = now, now = now)
        assertEquals(2, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(2, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())

        // Re-adding drained items should succeed because dedupSet was cleared
        val reAdded = NotificationCollectorService.addNotification("com.app", "Title 1", "Body 1", timestamp = now, now = now)
        assertTrue("Re-adding after drain should succeed as dedup set is cleared", reAdded)
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testAtomicIdCounterAndConcurrentAdditions() {
        val threadCount = 10
        val itemsPerThread = 10
        val executor = Executors.newFixedThreadPool(threadCount)
        val now = System.currentTimeMillis()

        for (t in 0 until threadCount) {
            executor.submit {
                for (i in 0 until itemsPerThread) {
                    NotificationCollectorService.addNotification(
                        packageName = "com.thread.$t",
                        title = "Title $i",
                        content = "Content $i",
                        timestamp = now,
                        now = now
                    )
                }
            }
        }

        executor.shutdown()
        assertTrue("Threads should complete within 5 seconds", executor.awaitTermination(5, TimeUnit.SECONDS))

        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(threadCount * itemsPerThread, drained.size)

        // Ensure 100% unique notification IDs generated under concurrent execution
        val uniqueIds = drained.map { it.id }.toSet()
        assertEquals("All generated notification IDs must be unique", drained.size, uniqueIds.size)
    }

    @Test
    fun testConcurrentAddAndDrain() {
        val threadCount = 8
        val executor = Executors.newFixedThreadPool(threadCount)

        for (t in 0 until threadCount) {
            if (t % 2 == 0) {
                executor.submit {
                    for (i in 0..50) {
                        NotificationCollectorService.addNotification(
                            packageName = "com.concurrent.$t",
                            title = "Title $i",
                            content = "Content $i"
                        )
                    }
                }
            } else {
                executor.submit {
                    for (i in 0..25) {
                        NotificationCollectorService.drainQueue()
                        Thread.yield()
                    }
                }
            }
        }

        executor.shutdown()
        assertTrue("Concurrent add/drain should finish safely without exceptions", executor.awaitTermination(5, TimeUnit.SECONDS))
    }
}
