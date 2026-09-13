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
