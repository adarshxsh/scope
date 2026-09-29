package com.scope.attentions

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.clearQueue()
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
    fun testTtlEvictionOnIngestion() {
        val now = 1_000_000_000_000L
        val ttlMs = NotificationCollectorService.MAX_TTL_MS

        val expiredData = NotificationData(
            id = "notif_expired",
            packageName = "com.example.app",
            title = "Expired On Arrival",
            content = "Content",
            timestamp = now - (ttlMs + 1000L),
            category = "msg",
            isOngoing = false
        )

        NotificationCollectorService.enqueue(expiredData, now)
        assertEquals(0, NotificationCollectorService.queueSize(now))
    }

    @Test
    fun testDeduplication() {
        val now = System.currentTimeMillis()
        val data1 = NotificationData(
            id = "notif_1",
            packageName = "com.example.app",
            title = "Same Title",
            content = "Same Content",
            timestamp = now,
            category = "msg",
            isOngoing = false
        )

        val data2 = NotificationData(
            id = "notif_2",
            packageName = "com.example.app",
            title = "Same Title",
            content = "Same Content",
            timestamp = now + 1000L,
            category = "msg",
            isOngoing = false
        )

        NotificationCollectorService.enqueue(data1, now)
        NotificationCollectorService.enqueue(data2, now)

        assertEquals(1, NotificationCollectorService.queueSize(now))
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
