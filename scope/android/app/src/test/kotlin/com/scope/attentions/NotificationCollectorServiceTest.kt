package com.scope.attentions

import org.junit.Assert.*
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
    fun testQueueInitialState() {
        assertEquals(0, NotificationCollectorService.queueSize())
        assertTrue(NotificationCollectorService.peekQueue().isEmpty())
    }

    @Test
    fun testEnqueueAndPeekQueue() {
        val now = System.currentTimeMillis()
        val data = NotificationData(
            id = NotificationCollectorService.nextNotificationId(),
            packageName = "com.example.app",
            title = "Test Title",
            content = "Test Content",
            timestamp = now,
            category = "msg",
            isOngoing = false
        )
        val added = NotificationCollectorService.enqueue(data)
        assertTrue(added)
        assertEquals(1, NotificationCollectorService.queueSize())

        val peeked = NotificationCollectorService.peekQueue()
        assertEquals(1, peeked.size)
        assertEquals("Test Title", peeked[0].title)
        // Ensure peek did not drain the queue
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testDuplicateSuppression() {
        val now = System.currentTimeMillis()
        val data1 = NotificationData(
            id = "notif_1",
            packageName = "com.example.app",
            title = "Same Title",
            content = "Same Content",
            timestamp = now,
            category = "msg",
            isOngoing = false
        )
        val data2 = NotificationData(
            id = "notif_2",
            packageName = "com.example.app",
            title = "Same Title",
            content = "Same Content",
            timestamp = now + 1000L,
            category = "msg",
            isOngoing = false
        )

        assertTrue(NotificationCollectorService.enqueue(data1))
        assertEquals(1, NotificationCollectorService.queueSize())

        // Duplicate attempt should return false and not grow queue
        assertFalse(NotificationCollectorService.enqueue(data2))
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testNonDuplicateItemsAllowed() {
        val now = System.currentTimeMillis()
        val data1 = NotificationData(
            id = "notif_1",
            packageName = "com.example.app",
            title = "Title 1",
            content = "Content 1",
            timestamp = now,
            category = "msg",
            isOngoing = false
        )
        val data2 = NotificationData(
            id = "notif_2",
            packageName = "com.example.app",
            title = "Title 2",
            content = "Content 1",
            timestamp = now + 1000L,
            category = "msg",
            isOngoing = false
        )

        assertTrue(NotificationCollectorService.enqueue(data1))
        assertTrue(NotificationCollectorService.enqueue(data2))
        assertEquals(2, NotificationCollectorService.queueSize())
    }

    @Test
    fun testQueueMaxCapacityAndFifoEviction() {
        val maxCapacity = NotificationCollectorService.MAX_QUEUE_SIZE
        assertEquals(100, maxCapacity)
        val now = System.currentTimeMillis()

        // Insert maxCapacity items
        for (i in 0 until maxCapacity) {
            val data = NotificationData(
                id = "notif_$i",
                packageName = "com.example.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = now + i,
                category = "msg",
                isOngoing = false
            )
            assertTrue(NotificationCollectorService.enqueue(data))
        }

        assertEquals(maxCapacity, NotificationCollectorService.queueSize())

        // Add 10 additional items beyond MAX_QUEUE_SIZE
        for (i in maxCapacity until maxCapacity + 10) {
            val data = NotificationData(
                id = "notif_$i",
                packageName = "com.example.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = now + i,
                category = "msg",
                isOngoing = false
            )
            assertTrue(NotificationCollectorService.enqueue(data))
            // Queue size must remain capped at maxCapacity
            assertEquals(maxCapacity, NotificationCollectorService.queueSize())
        }

        // Verify oldest items (Title 0 .. Title 9) were evicted
        val items = NotificationCollectorService.peekQueue()
        assertEquals(maxCapacity, items.size)
        // First item remaining should be Title 10
        assertEquals("Title 10", items.first().title)
        // Last item should be Title 109
        assertEquals("Title 109", items.last().title)
    }

    @Test
    fun testDrainQueueEmptiesQueue() {
        val now = System.currentTimeMillis()
        for (i in 0 until 5) {
            val data = NotificationData(
                id = "notif_$i",
                packageName = "com.example.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = now + i,
                category = "msg",
                isOngoing = false
            )
            NotificationCollectorService.enqueue(data)
        }

        assertEquals(5, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(5, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())
        assertEquals("Title 0", drained[0].title)
        assertEquals("Title 4", drained[4].title)
    }

    @Test
    fun testConcurrentEnqueueSafety() {
        val threadCount = 10
        val itemsPerThread = 20
        val executor = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)

        for (t in 0 until threadCount) {
            executor.submit {
                try {
                    for (i in 0 until itemsPerThread) {
                        val data = NotificationData(
                            id = "notif_t${t}_i$i",
                            packageName = "com.example.app$t",
                            title = "Title Thread $t Item $i",
                            content = "Content Thread $t Item $i",
                            timestamp = System.currentTimeMillis(),
                            category = "msg",
                            isOngoing = false
                        )
                        NotificationCollectorService.enqueue(data)
                    }
                } finally {
                    latch.countDown()
                }
            }
        }

        latch.await()
        executor.shutdown()

        // Total inserted = 200, capacity = 100 -> size must be exactly 100
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize())
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
}
