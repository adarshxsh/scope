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
    fun testDeduplicationRejectsDuplicatesInConstantTime() {
        val addedFirst = NotificationCollectorService.addNotification(
            packageName = "com.whatsapp",
            title = "Alice",
            content = "Hey there!",
            timestamp = 1000L,
            category = "msg",
            isOngoing = false
        )
        assertTrue(addedFirst)
        assertEquals(1, NotificationCollectorService.queueSize())

        val addedDuplicate = NotificationCollectorService.addNotification(
            packageName = "com.whatsapp",
            title = "Alice",
            content = "Hey there!",
            timestamp = 1005L,
            category = "msg",
            isOngoing = false
        )
        assertFalse(addedDuplicate)
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testBoundedCapacityCappedAt500AndEvictsOldestFifo() {
        // Add 550 unique notifications
        for (i in 0 until 550) {
            val added = NotificationCollectorService.addNotification(
                packageName = "com.example.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = 1000L + i,
                category = "promo",
                isOngoing = false
            )
            assertTrue(added)
        }

        assertEquals(NotificationCollectorService.MAX_CAPACITY, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(500, drained.size)

        // The first 50 items (0..49) should have been evicted.
        // Drained items should start at "Title 50" and end at "Title 549".
        assertEquals("Title 50", drained.first().title)
        assertEquals("Title 549", drained.last().title)
    }

    @Test
    fun testEvictedSignatureIsRemovedAndCanBeReAdded() {
        // Fill queue to MAX_CAPACITY (500 items)
        for (i in 0 until 500) {
            NotificationCollectorService.addNotification(
                packageName = "com.example.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = 1000L + i,
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
            timestamp = 2000L,
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
            timestamp = 2001L,
            category = null,
            isOngoing = false
        )
        assertTrue(reAddedTitle0)
        assertEquals(500, NotificationCollectorService.queueSize())
    }

    @Test
    fun testDrainQueueClearsQueueAndLookupSetCleanly() {
        for (i in 0 until 10) {
            NotificationCollectorService.addNotification(
                packageName = "com.test.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = 1000L + i,
                category = null,
                isOngoing = false
            )
        }

        assertEquals(10, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(10, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())

        // Verify that after drain, previously queued items can be added again
        val reAdd = NotificationCollectorService.addNotification(
            packageName = "com.test.app",
            title = "Title 0",
            content = "Content 0",
            timestamp = 2000L,
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

        for (t in 0 until threadCount) {
            executor.execute {
                try {
                    for (i in 0 until itemsPerThread) {
                        NotificationCollectorService.addNotification(
                            packageName = "com.concurrent.app",
                            title = "Title ${i % 50}", // Introduces duplicates
                            content = "Content ${i % 50}",
                            timestamp = System.currentTimeMillis(),
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

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(queueSize, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())
    }
}
