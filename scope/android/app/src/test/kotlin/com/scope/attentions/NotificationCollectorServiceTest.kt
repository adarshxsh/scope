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
    fun testQueueCapacityLimit() {
        val now = 1_000_000_000L

        // Add MAX_QUEUE_SIZE (100) notifications
        for (i in 1..NotificationCollectorService.MAX_QUEUE_SIZE) {
            val data = NotificationData(
                id = "notif_$i",
                packageName = "com.app.$i",
                title = "Title $i",
                content = "Content $i",
                timestamp = now,
                category = null,
                isOngoing = false
            )
            NotificationCollectorService.addNotification(data, now)
        }

        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize(now))

        // Add 101st notification
        val extraData = NotificationData(
            id = "notif_101",
            packageName = "com.app.101",
            title = "Title 101",
            content = "Content 101",
            timestamp = now,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(extraData, now)

        // Queue size should still be capped at MAX_QUEUE_SIZE (100)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize(now))

        // Drain queue and check contents
        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, drained.size)

        // First item (com.app.1) should have been evicted (FIFO)
        assertFalse(drained.any { it.packageName == "com.app.1" })
        // Second item (com.app.2) and last item (com.app.101) should be present
        assertTrue(drained.any { it.packageName == "com.app.2" })
        assertTrue(drained.any { it.packageName == "com.app.101" })
    }

    @Test
    fun testBoundedCapacityQueue() {
        val now = System.currentTimeMillis()
        val totalItems = 105

        for (i in 1..totalItems) {
            val data = NotificationData(
                id = "notif_$i",
                packageName = "com.example.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = now,
                category = "msg",
                isOngoing = false
            )
            NotificationCollectorService.enqueue(data, now)
        }

        assertEquals(100, NotificationCollectorService.queueSize(now))

        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(100, drained.size)

        // The first 5 items (Title 1 to Title 5) should have been dropped
        assertEquals("Title 6", drained.first().title)
        assertEquals("Title 105", drained.last().title)
    }

    @Test
    fun testTtlEvictionDuringCapture() {
        val baseTime = 1_000_000_000L
        val expiredTime = baseTime - (NotificationCollectorService.MAX_AGE_MS + 1000L)

        // Add an expired notification directly
        val expiredData = NotificationData(
            id = "old_1",
            packageName = "com.app.old",
            title = "Old Title",
            content = "Old Content",
            timestamp = expiredTime,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(expiredData, baseTime)

        // Since pruneExpired runs on addNotification, adding an expired item relative to baseTime should not remain
        assertEquals(0, NotificationCollectorService.queueSize(baseTime))

        // Manually place old item with older timestamp and add fresh item
        val freshData = NotificationData(
            id = "fresh_1",
            packageName = "com.app.fresh",
            title = "Fresh Title",
            content = "Fresh Content",
            timestamp = baseTime,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(freshData, baseTime)

        assertEquals(1, NotificationCollectorService.queueSize(baseTime))

        // Now add another item at baseTime + MAX_AGE_MS + 2000L (so fresh_1 expires)
        val futureTime = baseTime + NotificationCollectorService.MAX_AGE_MS + 2000L
        val newerData = NotificationData(
            id = "newer_1",
            packageName = "com.app.newer",
            title = "Newer Title",
            content = "Newer Content",
            timestamp = futureTime,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(newerData, futureTime)

        // fresh_1 should be evicted during pruneExpired on capture
        assertEquals(1, NotificationCollectorService.queueSize(futureTime))
        val drained = NotificationCollectorService.drainQueue(futureTime)
        assertEquals(1, drained.size)
        assertEquals("com.app.newer", drained[0].packageName)
    }

    @Test
    fun testTtlEvictionDuringDrain() {
        val postTime = 1_000_000_000L

        val notif = NotificationData(
            id = "n1",
            packageName = "com.app.test",
            title = "Title",
            content = "Content",
            timestamp = postTime,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(notif, postTime)
        assertEquals(1, NotificationCollectorService.queueSize(postTime))

        // Drain at time postTime + MAX_AGE_MS + 10,000ms (15m10s later)
        val drainTime = postTime + NotificationCollectorService.MAX_AGE_MS + 10_000L
        val drained = NotificationCollectorService.drainQueue(drainTime)

        assertTrue("Expired item should be filtered out on drain", drained.isEmpty())
        assertEquals(0, NotificationCollectorService.queueSize(drainTime))
    }

    @Test
    fun testTtlEvictionInDrainQueueAndQueueSize() {
        val now = 1_000_000_000_000L
        val ttlMs = NotificationCollectorService.MAX_TTL_MS // 900,000 ms = 15 minutes

        val expiredData1 = NotificationData(
            id = "notif_exp1",
            packageName = "com.example.app",
            title = "Expired Notification 1",
            content = "Old content 1",
            timestamp = now - (ttlMs + 60_000L), // 16 mins old
            category = "msg",
            isOngoing = false
        )

        val expiredData2 = NotificationData(
            id = "notif_exp2",
            packageName = "com.example.app",
            title = "Expired Notification 2",
            content = "Old content 2",
            timestamp = now - (ttlMs + 10_000L), // 15 mins 10 secs old
            category = "msg",
            isOngoing = false
        )

        val activeData = NotificationData(
            id = "notif_active",
            packageName = "com.example.app",
            title = "Active Notification",
            content = "Fresh content",
            timestamp = now - (5 * 60 * 1000L), // 5 mins old
            category = "msg",
            isOngoing = false
        )

        NotificationCollectorService.enqueue(expiredData1, now)
        NotificationCollectorService.enqueue(expiredData2, now)
        NotificationCollectorService.enqueue(activeData, now)

        assertEquals(1, NotificationCollectorService.queueSize(now))

        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(1, drained.size)
        assertEquals("Active Notification", drained[0].title)
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
    fun testPiiRedactionOnEnqueue() {
        val now = System.currentTimeMillis()
        val data = NotificationData(
            id = "notif_pii",
            packageName = "com.bank.app",
            title = "OTP code 849201 for card 4111-2222-3333-4444",
            content = "Payment of $500.00 to user@example.com at https://pay.com",
            timestamp = now,
            category = "msg",
            isOngoing = false
        )

        NotificationCollectorService.enqueue(data, now)

        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(1, drained.size)

        val result = drained[0]
        assertTrue("Title should contain [REDACTED_OTP]", result.title.contains("[REDACTED_OTP]"))
        assertTrue("Title should contain [REDACTED_CARD]", result.title.contains("[REDACTED_CARD]"))
        assertFalse("Title should not contain raw OTP", result.title.contains("849201"))
        assertFalse("Title should not contain raw card", result.title.contains("4111-2222-3333-4444"))

        assertTrue("Content should contain [REDACTED_AMOUNT]", result.content.contains("[REDACTED_AMOUNT]"))
        assertTrue("Content should contain [REDACTED_EMAIL]", result.content.contains("[REDACTED_EMAIL]"))
        assertTrue("Content should contain [REDACTED_URL]", result.content.contains("[REDACTED_URL]"))
        assertFalse("Content should not contain raw email", result.content.contains("user@example.com"))
    }

    @Test
    fun testClearQueue() {
        val now = System.currentTimeMillis()
        val data = NotificationData(
            id = "notif_1",
            packageName = "com.example.app",
            title = "Title",
            content = "Content",
            timestamp = now,
            category = "msg",
            isOngoing = false
        )

        NotificationCollectorService.enqueue(data, now)
        assertEquals(1, NotificationCollectorService.queueSize(now))

        NotificationCollectorService.clearQueue()
        assertEquals(0, NotificationCollectorService.queueSize(now))
    }
}
