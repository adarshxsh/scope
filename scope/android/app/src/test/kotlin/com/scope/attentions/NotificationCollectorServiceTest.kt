package com.scope.attentions

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.clearBuffer()
    }

    private fun createNotificationData(id: String, title: String, content: String): NotificationData {
        return NotificationData(
            id = id,
            packageName = "com.test.app",
            title = title,
            content = content,
            timestamp = System.currentTimeMillis(),
            category = "msg",
            isOngoing = false
        )
    }

    @Test
    fun testPeekDoesNotRemoveNotifications() {
        val data1 = createNotificationData("n1", "Title 1", "Content 1")
        val data2 = createNotificationData("n2", "Title 2", "Content 2")

        NotificationCollectorService.addNotificationForTest(data1)
        NotificationCollectorService.addNotificationForTest(data2)

        // First peek
        val peek1 = NotificationCollectorService.peekQueue()
        assertEquals(2, peek1.size)
        assertEquals("n1", peek1[0].id)
        assertEquals("n2", peek1[1].id)

        // Second peek — notifications should still be present in native memory
        val peek2 = NotificationCollectorService.peekQueue()
        assertEquals(2, peek2.size)
        assertEquals("n1", peek2[0].id)
        assertEquals("n2", peek2[1].id)
    }

    @Test
    fun testAcknowledgeNotificationsRemovesEntries() {
        val data1 = createNotificationData("n1", "Title 1", "Content 1")
        val data2 = createNotificationData("n2", "Title 2", "Content 2")
        val data3 = createNotificationData("n3", "Title 3", "Content 3")

        NotificationCollectorService.addNotificationForTest(data1)
        NotificationCollectorService.addNotificationForTest(data2)
        NotificationCollectorService.addNotificationForTest(data3)

        assertEquals(3, NotificationCollectorService.queueSize())

        // Explicitly acknowledge n1 and n3
        val ackCount = NotificationCollectorService.acknowledgeNotifications(listOf("n1", "n3"))
        assertEquals(2, ackCount)

        // Verify only n2 remains
        val remaining = NotificationCollectorService.peekQueue()
        assertEquals(1, remaining.size)
        assertEquals("n2", remaining[0].id)
    }

    @Test
    fun testUnacknowledgedPersistAcrossCycles() {
        val data1 = createNotificationData("n1", "Title 1", "Content 1")
        NotificationCollectorService.addNotificationForTest(data1)

        // Cycle 1: Peek without acknowledge (e.g. Dart processing/storage fails)
        val cycle1 = NotificationCollectorService.peekQueue()
        assertEquals(1, cycle1.size)

        // Cycle 2: Subsequent poll cycle re-fetches unacknowledged notification
        val cycle2 = NotificationCollectorService.peekQueue()
        assertEquals(1, cycle2.size)
        assertEquals("n1", cycle2[0].id)

        // Cycle 3: Explicit acknowledgment succeeds
        NotificationCollectorService.acknowledgeNotifications(listOf("n1"))
        val cycle3 = NotificationCollectorService.peekQueue()
        assertTrue(cycle3.isEmpty())
    }

    @Test
    fun testBufferCapacityLimitEnforcesMaxCapacity() {
        for (i in 1..1005) {
            val data = createNotificationData("notif_$i", "Title $i", "Content $i")
            NotificationCollectorService.addNotificationForTest(data)
        }

        // Buffer size must be bounded at MAX_BUFFER_CAPACITY (1000)
        assertEquals(1000, NotificationCollectorService.queueSize())

        val pending = NotificationCollectorService.peekQueue()
        assertEquals(1000, pending.size)
        // Oldest 5 items (notif_1 .. notif_5) should have been evicted
        assertEquals("notif_6", pending.first().id)
        assertEquals("notif_1005", pending.last().id)
    }

    @Test
    fun testAcknowledgeEmptyListReturnsZero() {
        val data1 = createNotificationData("n1", "Title 1", "Content 1")
        NotificationCollectorService.addNotificationForTest(data1)

        val count = NotificationCollectorService.acknowledgeNotifications(emptyList())
        assertEquals(0, count)
        assertEquals(1, NotificationCollectorService.queueSize())
    }
}
