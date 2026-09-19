package com.scope.attentions

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        // Drain any leftover queue items before each test
        NotificationCollectorService.drainQueue()
    }

    @Test
    fun testEnqueueAndDrainQueue() {
        assertEquals(0, NotificationCollectorService.queueSize())

        val added = NotificationCollectorService.enqueueNotification(
            packageName = "com.whatsapp",
            title = "Alice",
            content = "Hello there"
        )

        assertTrue(added)
        assertEquals(1, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(1, drained.size)
        assertEquals("com.whatsapp", drained[0].packageName)
        assertEquals("Alice", drained[0].title)
        assertEquals("Hello there", drained[0].content)
        assertEquals(0, NotificationCollectorService.queueSize())
    }

    @Test
    fun testDeduplication() {
        val firstAdd = NotificationCollectorService.enqueueNotification(
            packageName = "com.whatsapp",
            title = "Bob",
            content = "Call me back"
        )
        assertTrue(firstAdd)

        val duplicateAdd = NotificationCollectorService.enqueueNotification(
            packageName = "com.whatsapp",
            title = "Bob",
            content = "Call me back"
        )
        assertFalse(duplicateAdd)
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testRingQueueCapacityAndEviction() {
        val maxCap = NotificationCollectorService.MAX_QUEUE_SIZE

        // Fill queue to capacity
        for (i in 1..maxCap) {
            val added = NotificationCollectorService.enqueueNotification(
                packageName = "com.app",
                title = "Title $i",
                content = "Content $i"
            )
            assertTrue(added)
        }

        assertEquals(maxCap, NotificationCollectorService.queueSize())

        // Enqueue one more item to trigger eviction of oldest ("Title 1")
        val newAdded = NotificationCollectorService.enqueueNotification(
            packageName = "com.app",
            title = "Title Overflow",
            content = "Content Overflow"
        )
        assertTrue(newAdded)
        assertEquals(maxCap, NotificationCollectorService.queueSize())

        // Re-enqueuing "Title 1" should now succeed since it was evicted
        val reAdded = NotificationCollectorService.enqueueNotification(
            packageName = "com.app",
            title = "Title 1",
            content = "Content 1"
        )
        assertTrue(reAdded)
        assertEquals(maxCap, NotificationCollectorService.queueSize())

        val items = NotificationCollectorService.drainQueue()
        assertEquals(maxCap, items.size)
        // Check that oldest item in queue is "Title 3" (since Title 1 was evicted, then Title 2 was evicted when Title 1 was re-added)
        assertEquals("Title 3", items[0].title)
        assertEquals("Title 1", items[items.size - 1].title)
    }
}
