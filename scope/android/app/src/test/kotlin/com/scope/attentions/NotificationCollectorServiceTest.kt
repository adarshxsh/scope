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
        // Fill queue to capacity (250)
        for (i in 0 until 250) {
            val added = NotificationCollectorService.enqueueNotification(
                packageName = "com.test.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = i.toLong(),
                category = "msg",
                isOngoing = false
            )
            assertTrue("Expected item $i to be added", added)
        }

        assertEquals(250, NotificationCollectorService.queueSize())

        // Add 251st item which should trigger drop-oldest eviction
        val addedOverflow = NotificationCollectorService.enqueueNotification(
            packageName = "com.test.app",
            title = "Title 250",
            content = "Content 250",
            timestamp = 250L,
            category = "msg",
            isOngoing = false
        )
        assertTrue("Expected 251st item to be added", addedOverflow)

        // Queue size remains capped at 250
        assertEquals(250, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(250, drained.size)

        // First item should now be "Title 1" (Title 0 was evicted)
        assertEquals("Title 1", drained.first().title)
        assertEquals("notif_2", drained.first().id)

        // Last item should be "Title 250"
        assertEquals("Title 250", drained.last().title)
        assertEquals("notif_251", drained.last().id)
    }

    @Test
    fun testO1Deduplication() {
        val addedFirst = NotificationCollectorService.enqueueNotification(
            packageName = "com.test.chat",
            title = "Alice",
            content = "Hello world",
            timestamp = 1000L,
            category = "msg",
            isOngoing = false
        )
        assertTrue(addedFirst)

        // Attempt duplicate notification
        val addedDuplicate = NotificationCollectorService.enqueueNotification(
            packageName = "com.test.chat",
            title = "Alice",
            content = "Hello world",
            timestamp = 1005L,
            category = "msg",
            isOngoing = false
        )
        assertFalse("Duplicate notification should be rejected", addedDuplicate)

        assertEquals(1, NotificationCollectorService.queueSize())

        // Non-duplicate with different content should succeed
        val addedNew = NotificationCollectorService.enqueueNotification(
            packageName = "com.test.chat",
            title = "Alice",
            content = "How are you?",
            timestamp = 1010L,
            category = "msg",
            isOngoing = false
        )
        assertTrue(addedNew)
        assertEquals(2, NotificationCollectorService.queueSize())
    }

    @Test
    fun testDrainQueueEmptiesQueueAndClearsDeduplicationSet() {
        NotificationCollectorService.enqueueNotification(
            packageName = "com.test.email",
            title = "Newsletter",
            content = "Weekly digest",
            timestamp = 1000L,
            category = "promo",
            isOngoing = false
        )

        assertEquals(1, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(1, drained.size)
        assertEquals("Newsletter", drained[0].title)

        // Queue is empty
        assertEquals(0, NotificationCollectorService.queueSize())

        // Re-adding same notification after drain should succeed
        val addedAfterDrain = NotificationCollectorService.enqueueNotification(
            packageName = "com.test.email",
            title = "Newsletter",
            content = "Weekly digest",
            timestamp = 2000L,
            category = "promo",
            isOngoing = false
        )
        assertTrue("Should allow re-enqueue after queue drain", addedAfterDrain)
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testEvictionRemovesKeyFromDeduplicationSet() {
        // Fill queue with 250 items
        for (i in 0 until 250) {
            NotificationCollectorService.enqueueNotification(
                packageName = "com.test.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = i.toLong(),
                category = "sys",
                isOngoing = false
            )
        }

        // Add 251st item, evicting "Title 0"
        NotificationCollectorService.enqueueNotification(
            packageName = "com.test.app",
            title = "Title 250",
            content = "Content 250",
            timestamp = 250L,
            category = "sys",
            isOngoing = false
        )

        // Re-add "Title 0" which was evicted; it should succeed
        val readdedEvicted = NotificationCollectorService.enqueueNotification(
            packageName = "com.test.app",
            title = "Title 0",
            content = "Content 0",
            timestamp = 251L,
            category = "sys",
            isOngoing = false
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

        for (t in 0 until threadCount) {
            executor.execute {
                try {
                    for (i in 0 until itemsPerThread) {
                        NotificationCollectorService.enqueueNotification(
                            packageName = "com.test.thread$t",
                            title = "Title $i",
                            content = "Content $i",
                            timestamp = System.currentTimeMillis(),
                            category = "sys",
                            isOngoing = false
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

        val drained = NotificationCollectorService.drainQueue()
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
