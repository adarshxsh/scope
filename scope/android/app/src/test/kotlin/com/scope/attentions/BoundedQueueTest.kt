package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class BoundedQueueTest {

    @Test
    fun testCapacityNeverExceedsLimitUnder1000Insertions() {
        val queue = BoundedNotificationQueue<NotificationData>(100)

        for (i in 1..1000) {
            queue.add(
                NotificationData(
                    id = "id_$i",
                    packageName = "com.example.app",
                    title = "Title $i",
                    content = "Content $i",
                    timestamp = System.currentTimeMillis(),
                    category = "msg",
                    isOngoing = false
                )
            )
            assertTrue("Queue size exceeded 100 on iteration $i", queue.size <= 100)
        }

        assertEquals(100, queue.size)
    }

    @Test
    fun testFifoEvictionOrder() {
        val queue = BoundedQueue<String>(100)

        for (i in 1..150) {
            queue.add("item_$i")
        }

        assertEquals(100, queue.size)

        val drained = queue.drainQueue()
        assertEquals(100, drained.size)
        // First item in queue should be item_51 (since 1..50 were evicted)
        assertEquals("item_51", drained.first())
        assertEquals("item_150", drained.last())
        assertTrue(queue.isEmpty())
    }

    @Test
    fun testConcurrentInsertions() {
        val queue = BoundedNotificationQueue<Int>(100)
        val threadCount = 10
        val insertionsPerThread = 100
        val executor = Executors.newFixedThreadPool(threadCount)

        for (t in 0 until threadCount) {
            executor.submit {
                for (i in 0 until insertionsPerThread) {
                    queue.add(t * 1000 + i)
                }
            }
        }

        executor.shutdown()
        executor.awaitTermination(5, TimeUnit.SECONDS)

        assertEquals(100, queue.size)
    }

    @Test
    fun testDrainQueueEmptiesQueue() {
        val queue = BoundedNotificationQueue<Int>(100)
        for (i in 1..50) {
            queue.add(i)
        }
        assertEquals(50, queue.size)

        val items = queue.drainQueue()
        assertEquals(50, items.size)
        assertEquals(0, queue.size)
        assertTrue(queue.isEmpty())
    }
}
