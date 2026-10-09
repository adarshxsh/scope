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

    private fun createNotification(
        id: String,
        packageName: String = "com.example.app",
        title: String = "Test Title",
        content: String = "Test Content",
        timestamp: Long = System.currentTimeMillis()
    ): NotificationData {
        return NotificationData(
            id = id,
            packageName = packageName,
            title = title,
            content = content,
            timestamp = timestamp,
            category = "msg",
            isOngoing = false
        )
    }

    @Test
    fun testQueueCapacityLimit() {
        val now = 1_000_000_000L

        // Add MAX_QUEUE_SIZE (200) notifications
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

        // Add 201st notification
        val extraData = NotificationData(
            id = "notif_201",
            packageName = "com.app.201",
            title = "Title 201",
            content = "Content 201",
            timestamp = now,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(extraData, now)

        // Queue size should still be capped at MAX_QUEUE_SIZE (200)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize())

        // Drain queue and check contents
        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, drained.size)

        // First item (com.app.1) should have been evicted (FIFO)
        assertFalse(drained.any { it.packageName == "com.app.1" })
        // Second item (com.app.2) and last item (com.app.201) should be present
        assertTrue(drained.any { it.packageName == "com.app.2" })
        assertTrue(drained.any { it.packageName == "com.app.201" })
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
    fun testHardLimitCapacity200() {
        assertEquals(0, NotificationCollectorService.queueSize())

        val now = System.currentTimeMillis()
        for (i in 0 until 250) {
            val notif = createNotification(
                id = "notif_$i",
                packageName = "com.app.$i",
                title = "Title $i",
                content = "Content $i",
                timestamp = now
            )
            NotificationCollectorService.addNotification(notif, now)
        }

        assertEquals(200, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(200, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())

        // The first 50 items (0..49) should have been evicted.
        // The drained list should start from item 50 ("com.app.50").
        assertEquals("com.app.50", drained.first().packageName)
        assertEquals("com.app.249", drained.last().packageName)
    }

    @Test
    fun testFifoEviction() {
        val now = System.currentTimeMillis()
        // Fill queue to capacity (200 items: 0..199)
        for (i in 0 until 200) {
            NotificationCollectorService.addNotification(
                createNotification(id = "id_$i", title = "Title $i", content = "Body $i", timestamp = now),
                now
            )
        }

        assertEquals(200, NotificationCollectorService.queueSize())

        // Adding 201st item should evict oldest item ("Title 0", "Body 0")
        val added = NotificationCollectorService.addNotification(
            createNotification(id = "id_200", title = "Title 200", content = "Body 200", timestamp = now),
            now
        )
        assertTrue(added)
        assertEquals(200, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals("Title 1", drained.first().title)
        assertEquals("Title 200", drained.last().title)
    }

    @Test
    fun testConstantTimeDeduplication() {
        val now = System.currentTimeMillis()
        val notif1 = createNotification(id = "1", packageName = "com.test", title = "Alert", content = "Msg", timestamp = now)
        val notif2 = createNotification(id = "2", packageName = "com.test", title = "Alert", content = "Msg", timestamp = now)

        assertTrue(NotificationCollectorService.addNotification(notif1, now))
        assertFalse("Duplicate notification should be rejected", NotificationCollectorService.addNotification(notif2, now))
        assertEquals(1, NotificationCollectorService.queueSize())

        // Different package name should be accepted
        val notif3 = createNotification(id = "3", packageName = "com.other", title = "Alert", content = "Msg", timestamp = now)
        assertTrue(NotificationCollectorService.addNotification(notif3, now))

        // Different content should be accepted
        val notif4 = createNotification(id = "4", packageName = "com.test", title = "Alert", content = "New Msg", timestamp = now)
        assertTrue(NotificationCollectorService.addNotification(notif4, now))

        assertEquals(3, NotificationCollectorService.queueSize())
    }

    @Test
    fun testReAddAfterEviction() {
        val now = System.currentTimeMillis()
        val notif0 = createNotification(id = "0", packageName = "com.app.0", title = "Title 0", content = "Body 0", timestamp = now)
        assertTrue(NotificationCollectorService.addNotification(notif0, now))

        // Add 200 distinct items to cause eviction of notif0
        for (i in 1..200) {
            NotificationCollectorService.addNotification(
                createNotification(id = "id_$i", packageName = "com.app.$i", title = "Title $i", content = "Body $i", timestamp = now),
                now
            )
        }

        assertEquals(200, NotificationCollectorService.queueSize())

        // Since notif0 was evicted, its key should be removed from deduplication index
        val reAddNotif0 = createNotification(id = "readd_0", packageName = "com.app.0", title = "Title 0", content = "Body 0", timestamp = now)
        assertTrue("Evicted notification key should be re-addable", NotificationCollectorService.addNotification(reAddNotif0, now))
        assertEquals(200, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals("com.app.2", drained.first().packageName)
        assertEquals("com.app.0", drained.last().packageName)
    }

    @Test
    fun testAtomicDrainResetsQueueAndIndex() {
        val now = System.currentTimeMillis()
        val notif = createNotification(id = "1", packageName = "com.app", title = "Hello", content = "World", timestamp = now)
        assertTrue(NotificationCollectorService.addNotification(notif, now))
        assertEquals(1, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(1, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())

        // Re-adding same notification after drain should succeed because dedup index was cleared
        assertTrue(NotificationCollectorService.addNotification(notif, now))
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testThreadSafetyAndConcurrency() {
        val now = System.currentTimeMillis()
        val threadCount = 10
        val itemsPerThread = 100
        val executor = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)

        for (t in 0 until threadCount) {
            executor.execute {
                try {
                    for (i in 0 until itemsPerThread) {
                        val notif = createNotification(
                            id = "t${t}_$i",
                            packageName = "com.thread.$t",
                            title = "Title $i",
                            content = "Content $i",
                            timestamp = now
                        )
                        NotificationCollectorService.addNotification(notif, now)
                        if (i % 25 == 0) {
                            NotificationCollectorService.queueSize()
                        }
                    }
                } finally {
                    latch.countDown()
                }
            }
        }

        latch.await()
        executor.shutdown()

        val size = NotificationCollectorService.queueSize()
        assertTrue("Queue size should never exceed 200", size <= 200)

        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(size, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())
    }
}
