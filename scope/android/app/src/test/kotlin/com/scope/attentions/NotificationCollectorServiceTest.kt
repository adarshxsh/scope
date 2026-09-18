package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.clearQueue()
        NotificationCollectorService.maxQueueCapacity = NotificationCollectorService.DEFAULT_MAX_QUEUE_CAPACITY
    }

    @Test
    fun testPeekQueueIsNonDestructive() {
        val notif1 = NotificationData("n1", "com.test", "Title 1", "Body 1", 1000L)
        val notif2 = NotificationData("n2", "com.test", "Title 2", "Body 2", 2000L)

        NotificationCollectorService.addNotificationForTest(notif1)
        NotificationCollectorService.addNotificationForTest(notif2)

        assertEquals(2, NotificationCollectorService.queueSize())

        val peeked = NotificationCollectorService.peekQueue()
        assertEquals(2, peeked.size)
        assertEquals("n1", peeked[0].id)
        assertEquals("n2", peeked[1].id)

        // Queue size remains 2 after peeking
        assertEquals(2, NotificationCollectorService.queueSize())
    }

    @Test
    fun testAcknowledgeRemovesOnlySpecifiedIds() {
        val notif1 = NotificationData("n1", "com.test", "Title 1", "Body 1", 1000L)
        val notif2 = NotificationData("n2", "com.test", "Title 2", "Body 2", 2000L)
        val notif3 = NotificationData("n3", "com.test", "Title 3", "Body 3", 3000L)

        NotificationCollectorService.addNotificationForTest(notif1)
        NotificationCollectorService.addNotificationForTest(notif2)
        NotificationCollectorService.addNotificationForTest(notif3)

        assertEquals(3, NotificationCollectorService.queueSize())

        val ackedCount = NotificationCollectorService.acknowledge(listOf("n1", "n3"))
        assertEquals(2, ackedCount)

        assertEquals(1, NotificationCollectorService.queueSize())
        val remaining = NotificationCollectorService.peekQueue()
        assertEquals("n2", remaining[0].id)
    }

    @Test
    fun testMaxQueueCapacityEnforcement() {
        NotificationCollectorService.maxQueueCapacity = 3

        val notif1 = NotificationData("n1", "com.test", "Title 1", "Body 1", 1000L)
        val notif2 = NotificationData("n2", "com.test", "Title 2", "Body 2", 2000L)
        val notif3 = NotificationData("n3", "com.test", "Title 3", "Body 3", 3000L)
        val notif4 = NotificationData("n4", "com.test", "Title 4", "Body 4", 4000L)

        NotificationCollectorService.addNotificationForTest(notif1)
        NotificationCollectorService.addNotificationForTest(notif2)
        NotificationCollectorService.addNotificationForTest(notif3)
        assertEquals(3, NotificationCollectorService.queueSize())

        // Adding 4th item when max capacity is 3 should evict the oldest item (n1)
        NotificationCollectorService.addNotificationForTest(notif4)
        assertEquals(3, NotificationCollectorService.queueSize())

        val remaining = NotificationCollectorService.peekQueue()
        assertEquals(listOf("n2", "n3", "n4"), remaining.map { it.id })
    }

    @Test
    fun testAcknowledgeWithEmptyListDoesNothing() {
        val notif1 = NotificationData("n1", "com.test", "Title 1", "Body 1", 1000L)
        NotificationCollectorService.addNotificationForTest(notif1)

        val ackedCount = NotificationCollectorService.acknowledge(emptyList())
        assertEquals(0, ackedCount)
        assertEquals(1, NotificationCollectorService.queueSize())
    }
}
