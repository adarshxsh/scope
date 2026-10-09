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
            NotificationCollectorService.addNotification(data, now)
        }

        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize())

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
        NotificationCollectorService.addNotification(extraData, now)

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
    fun testDeduplicationRejectsDuplicatesInConstantTime() {
        val now = 1_000_000_000L
        val addedFirst = NotificationCollectorService.addNotification(
            packageName = "com.whatsapp",
            title = "Alice",
            content = "Hey there!",
            timestamp = now,
            category = "msg",
            isOngoing = false
        )
        assertTrue(addedFirst)
        assertEquals(1, NotificationCollectorService.queueSize())

        val addedDuplicate = NotificationCollectorService.addNotification(
            packageName = "com.whatsapp",
            title = "Alice",
            content = "Hey there!",
            timestamp = now + 5,
            category = "msg",
            isOngoing = false
        )
        assertFalse(addedDuplicate)
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testBoundedCapacityCappedAt500AndEvictsOldestFifo() {
        val now = 1_000_000_000L
        // Add 550 unique notifications
        for (i in 0 until 550) {
            val added = NotificationCollectorService.addNotification(
                packageName = "com.example.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = now + i,
                category = "promo",
                isOngoing = false
            )
            assertTrue(added)
        }

        assertEquals(NotificationCollectorService.MAX_CAPACITY, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue(now + 600)
        assertEquals(500, drained.size)

        // The first 50 items (0..49) should have been evicted.
        // Drained items should start at "Title 50" and end at "Title 549".
        assertEquals("Title 50", drained.first().title)
        assertEquals("Title 549", drained.last().title)
    }

    @Test
    fun testEvictedSignatureIsRemovedAndCanBeReAdded() {
        val now = 1_000_000_000L
        // Fill queue to MAX_CAPACITY (500 items)
        for (i in 0 until 500) {
            NotificationCollectorService.addNotification(
                packageName = "com.example.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = now + i,
                category = null,
                isOngoing = false
            )
        }
        assertEquals(500, NotificationCollectorService.queueSize())

        // Adding 501st item causes Title 0 to be evicted
        val added501 = NotificationCollectorService.addNotification(
            packageName = "com.example.app",
            title = "Title 500",
            content = "Content 500",
            timestamp = now + 1000,
            category = null,
            isOngoing = false
        )
        assertTrue(added501)
        assertEquals(500, NotificationCollectorService.queueSize())

        // Title 0 was evicted, so re-adding Title 0 should now succeed
        val reAddedTitle0 = NotificationCollectorService.addNotification(
            packageName = "com.example.app",
            title = "Title 0",
            content = "Content 0",
            timestamp = now + 1001,
            category = null,
            isOngoing = false
        )
        assertTrue(reAddedTitle0)
        assertEquals(500, NotificationCollectorService.queueSize())
    }

    @Test
    fun testDrainQueueClearsQueueAndLookupSetCleanly() {
        val now = 1_000_000_000L
        for (i in 0 until 10) {
            NotificationCollectorService.addNotification(
                packageName = "com.test.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = now + i,
                category = null,
                isOngoing = false
            )
        }

        assertEquals(10, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue(now + 100)
        assertEquals(10, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())

        // Verify that after drain, previously queued items can be added again
        val reAdd = NotificationCollectorService.addNotification(
            packageName = "com.test.app",
            title = "Title 0",
            content = "Content 0",
            timestamp = now + 200,
            category = null,
            isOngoing = false
        )
        assertTrue(reAdd)
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testConcurrentThreadSafetyWithoutLocksOrRaceConditions() {
        val threadCount = 10
        val itemsPerThread = 100
        val executor = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)
        val now = System.currentTimeMillis()

        for (t in 0 until threadCount) {
            executor.execute {
                try {
                    for (i in 0 until itemsPerThread) {
                        NotificationCollectorService.addNotification(
                            packageName = "com.concurrent.app",
                            title = "Title ${i % 50}", // Introduces duplicates
                            content = "Content ${i % 50}",
                            timestamp = now + i,
                            category = null,
                            isOngoing = false
                        )
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

        val queueSize = NotificationCollectorService.queueSize()
        assertTrue(queueSize in 1..NotificationCollectorService.MAX_CAPACITY)

        val drained = NotificationCollectorService.drainQueue(now + itemsPerThread + 100)
        assertEquals(queueSize, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())
    }
}
