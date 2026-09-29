package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.clearQueue()
    }

    @Test
    fun testCapacityLimitAndHeadEviction() {
        val now = 1_000_000L

        // Add 100 distinct notifications (MAX_CAPACITY)
        for (i in 1..100) {
            val data = NotificationData(
                id = "notif_$i",
                packageName = "com.app.$i",
                title = "Title $i",
                content = "Content $i",
                timestamp = now,
                category = "msg",
                isOngoing = false
            )
            val added = NotificationCollectorService.addNotification(data, now)
            assertTrue(added)
        }

        assertEquals(100, NotificationCollectorService.queueSize(now))

        // Add 101st notification
        val extraData = NotificationData(
            id = "notif_101",
            packageName = "com.app.101",
            title = "Title 101",
            content = "Content 101",
            timestamp = now,
            category = "msg",
            isOngoing = false
        )
        val added101 = NotificationCollectorService.addNotification(extraData, now)
        assertTrue(added101)

        // Capacity must remain 100
        assertEquals(100, NotificationCollectorService.queueSize(now))

        // Draining queue should yield notifications 2 through 101 (notification 1 was evicted)
        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(100, drained.size)
        assertEquals("notif_2", drained.first().id)
        assertEquals("notif_101", drained.last().id)
    }

    @Test
    fun testTTLEvictionOnDrain() {
        val baseTime = 2_000_000L

        // Add 3 notifications with different timestamps:
        // 1. Expired (20 minutes old)
        // 2. Expired (16 minutes old)
        // 3. Valid (5 minutes old)
        val notifExpired1 = NotificationData(
            id = "expired_1",
            packageName = "com.app.a",
            title = "Old Title 1",
            content = "Old Content 1",
            timestamp = baseTime - (20 * 60 * 1000L),
            category = null,
            isOngoing = false
        )
        val notifExpired2 = NotificationData(
            id = "expired_2",
            packageName = "com.app.b",
            title = "Old Title 2",
            content = "Old Content 2",
            timestamp = baseTime - (16 * 60 * 1000L),
            category = null,
            isOngoing = false
        )
        val notifValid = NotificationData(
            id = "valid_3",
            packageName = "com.app.c",
            title = "Recent Title",
            content = "Recent Content",
            timestamp = baseTime - (5 * 60 * 1000L),
            category = null,
            isOngoing = false
        )

        NotificationCollectorService.addNotification(notifExpired1, baseTime - (20 * 60 * 1000L))
        NotificationCollectorService.addNotification(notifExpired2, baseTime - (16 * 60 * 1000L))
        NotificationCollectorService.addNotification(notifValid, baseTime - (5 * 60 * 1000L))

        // queueSize at baseTime evicts expired items
        assertEquals(1, NotificationCollectorService.queueSize(baseTime))

        val drained = NotificationCollectorService.drainQueue(baseTime)
        assertEquals(1, drained.size)
        assertEquals("valid_3", drained.first().id)
    }

    @Test
    fun testTTLEvictionOnAdd() {
        val baseTime = 3_000_000L
        val oldTime = baseTime - (20 * 60 * 1000L) // 20 minutes ago

        val oldNotif = NotificationData(
            id = "old_1",
            packageName = "com.app.old",
            title = "Old",
            content = "Old",
            timestamp = oldTime,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(oldNotif, oldTime)

        // Adding a new notification at baseTime triggers eviction of oldNotif
        val newNotif = NotificationData(
            id = "new_1",
            packageName = "com.app.new",
            title = "New",
            content = "New",
            timestamp = baseTime,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(newNotif, baseTime)

        assertEquals(1, NotificationCollectorService.queueSize(baseTime))
        val drained = NotificationCollectorService.drainQueue(baseTime)
        assertEquals(1, drained.size)
        assertEquals("new_1", drained.first().id)
    }

    @Test
    fun testDuplicatePrevention() {
        val now = 1_000_000L
        val notif1 = NotificationData(
            id = "notif_1",
            packageName = "com.app.dup",
            title = "Duplicate Title",
            content = "Duplicate Content",
            timestamp = now,
            category = null,
            isOngoing = false
        )
        val notif2 = NotificationData(
            id = "notif_2",
            packageName = "com.app.dup",
            title = "Duplicate Title",
            content = "Duplicate Content",
            timestamp = now + 1000L,
            category = null,
            isOngoing = false
        )

        assertTrue(NotificationCollectorService.addNotification(notif1, now))
        assertFalse(NotificationCollectorService.addNotification(notif2, now + 1000L))
        assertEquals(1, NotificationCollectorService.queueSize(now + 1000L))
    }

    @Test
    fun testDuplicateHandlingAndResubmissionAfterExpiry() {
        val t0 = 1_000_000_000L

        val notif1 = NotificationData(
            id = "1",
            packageName = "com.app.chat",
            title = "Hello",
            content = "World",
            timestamp = t0,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(notif1, t0)

        // Attempting to add duplicate at t0 should be ignored
        val dupNotif = NotificationData(
            id = "2",
            packageName = "com.app.chat",
            title = "Hello",
            content = "World",
            timestamp = t0,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(dupNotif, t0)
        assertEquals(1, NotificationCollectorService.queueSize(t0))

        // Advance time past expiry
        val tFuture = t0 + NotificationCollectorService.MAX_AGE_MS + 5000L

        // Adding same notification after expiry should prune old and succeed
        val newNotif = NotificationData(
            id = "3",
            packageName = "com.app.chat",
            title = "Hello",
            content = "World",
            timestamp = tFuture,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(newNotif, tFuture)

        assertEquals(1, NotificationCollectorService.queueSize(tFuture))
        val drained = NotificationCollectorService.drainQueue(tFuture)
        assertEquals(1, drained.size)
        assertEquals("3", drained[0].id)
    }

    @Test
    fun testClearQueue() {
        val now = 1_000_000L
        val notif = NotificationData(
            id = "notif_1",
            packageName = "com.app.test",
            title = "Title",
            content = "Content",
            timestamp = now,
            category = null,
            isOngoing = false
        )

        NotificationCollectorService.addNotification(notif, now)
        assertEquals(1, NotificationCollectorService.queueSize(now))

        NotificationCollectorService.clearQueue()
        assertEquals(0, NotificationCollectorService.queueSize(now))
    }
}
