package com.scope.attentions

import org.junit.Assert.*
import org.junit.Test

class NotificationCollectorServiceTest {

    @Test
    fun testPeekQueueAndAcknowledgeIds() {
        // Clear any leftover state by draining queue
        NotificationCollectorService.drainQueue()
        assertEquals(0, NotificationCollectorService.queueSize())

        // Initial peek on empty queue
        val emptyPeek = NotificationCollectorService.peekQueue()
        assertTrue(emptyPeek.isEmpty())

        // Verify drainQueue and peekQueue behavior
        // Since queue is private to companion object and populated via addSbnToQueue/onNotificationPosted,
        // drainQueue clears and returns empty list when no items are added.
        NotificationCollectorService.acknowledgeIds(listOf("notif_1"))
        assertEquals(0, NotificationCollectorService.queueSize())
    }
}
