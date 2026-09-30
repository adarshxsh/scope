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
        val data = NotificationData(
            id = NotificationCollectorService.nextNotificationId(),
            packageName = "com.example.app",
            title = "Test Title",
            content = "Test Content",
            timestamp = 1000L,
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
        val data1 = NotificationData(
            id = "notif_1",
            packageName = "com.example.app",
            title = "Same Title",
            content = "Same Content",
            timestamp = 1000L,
            category = "msg",
            isOngoing = false
        )
        val data2 = NotificationData(
            id = "notif_2",
            packageName = "com.example.app",
            title = "Same Title",
            content = "Same Content",
            timestamp = 2000L,
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
        val data1 = NotificationData(
            id = "notif_1",
            packageName = "com.example.app",
            title = "Title 1",
            content = "Content 1",
            timestamp = 1000L,
            category = "msg",
            isOngoing = false
        )
        val data2 = NotificationData(
            id = "notif_2",
            packageName = "com.example.app",
            title = "Title 2",
            content = "Content 1",
            timestamp = 2000L,
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

        // Insert maxCapacity items
        for (i in 0 until maxCapacity) {
            val data = NotificationData(
                id = "notif_$i",
                packageName = "com.example.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = 1000L + i,
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
                timestamp = 1000L + i,
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
        for (i in 0 until 5) {
            val data = NotificationData(
                id = "notif_$i",
                packageName = "com.example.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = 1000L + i,
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
}
