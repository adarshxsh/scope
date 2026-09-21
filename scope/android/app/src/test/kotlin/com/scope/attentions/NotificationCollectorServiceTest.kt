package com.scope.attentions

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.reset()
    }

    @Test
    fun testInitialState() {
        assertEquals(0, NotificationCollectorService.queueSize())
        assertEquals(0L, NotificationCollectorService.droppedCount())
        assertTrue(NotificationCollectorService.drainQueue().isEmpty())
    }

    @Test
    fun testDefaultCapacityIs500() {
        assertEquals(500, NotificationCollectorService.DEFAULT_CAPACITY)
    }

    @Test
    fun testDrainAndReset() {
        assertEquals(0, NotificationCollectorService.queueSize())
        val drained = NotificationCollectorService.drainQueue()
        assertTrue(drained.isEmpty())
        assertEquals(0, NotificationCollectorService.queueSize())
        assertEquals(0L, NotificationCollectorService.droppedCount())
    }
}
