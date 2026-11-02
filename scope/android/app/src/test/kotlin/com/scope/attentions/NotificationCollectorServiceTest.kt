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

        // Add MAX_QUEUE_SIZE notifications
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

        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize())

        // Add extra notification
        val extraData = NotificationData(
            id = "notif_extra",
            packageName = "com.app.extra",
            title = "Title extra",
            content = "Content extra",
            timestamp = now,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.addNotification(extraData, now)

        // Queue size should still be capped at MAX_QUEUE_SIZE
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize())

        // Drain queue and check contents
        val drained = NotificationCollectorService.drainQueue(now)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, drained.size)

        // First item (com.app.1) should have been evicted (FIFO)
        assertFalse(drained.any { it.packageName == "com.app.1" })
        // Second item (com.app.2) and last item (com.app.extra) should be present
        assertTrue(drained.any { it.packageName == "com.app.2" })
        assertTrue(drained.any { it.packageName == "com.app.extra" })
    }

    @Test
    fun testQueueBoundingAndDropOldestEviction() {
        val totalToInsert = 300
        val now = System.currentTimeMillis()
        for (i in 1..totalToInsert) {
            val added = NotificationCollectorService.enqueueNotification(
                packageName = "com.test.app$i",
                title = "Title $i",
                content = "Content $i",
                timestamp = now + i,
                category = "msg",
                isOngoing = false,
                now = now + i
            )
            assertTrue("Item $i should be added", added)
        }

        // Queue size must be capped at MAX_QUEUE_SIZE
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue(now + totalToInsert)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, drained.size)

        // Verify drop-oldest: oldest items evicted
        val expectedFirstIndex = totalToInsert - NotificationCollectorService.MAX_QUEUE_SIZE + 1
        assertEquals("com.test.app$expectedFirstIndex", drained.first().packageName)
        assertEquals("com.test.app300", drained.last().packageName)
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

        // Expired relative to baseTime should not remain
        assertEquals(0, NotificationCollectorService.queueSize())

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

        assertEquals(1, NotificationCollectorService.queueSize())

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

        assertEquals(1, NotificationCollectorService.queueSize())
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
        assertEquals(1, NotificationCollectorService.queueSize())

        val drainTime = postTime + NotificationCollectorService.MAX_AGE_MS + 10_000L
        val drained = NotificationCollectorService.drainQueue(drainTime)

        assertTrue("Expired item should be filtered out on drain", drained.isEmpty())
        assertEquals(0, NotificationCollectorService.queueSize())
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
        assertEquals(1, NotificationCollectorService.queueSize())

        val tFuture = t0 + NotificationCollectorService.MAX_AGE_MS + 5000L

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

        assertEquals(1, NotificationCollectorService.queueSize())
        val drained = NotificationCollectorService.drainQueue(tFuture)
        assertEquals(1, drained.size)
        assertEquals("3", drained[0].id)
    }

    @Test
    fun testO1Deduplication() {
        val now = System.currentTimeMillis()
        val addedFirst = NotificationCollectorService.enqueueNotification(
            packageName = "com.example.chat",
            title = "New Message",
            content = "Hello there",
            timestamp = now,
            category = "msg",
            isOngoing = false,
            now = now
        )
        assertTrue(addedFirst)
        assertEquals(1, NotificationCollectorService.queueSize())

        val addedDuplicate = NotificationCollectorService.enqueueNotification(
            packageName = "com.example.chat",
            title = "New Message",
            content = "Hello there",
            timestamp = now + 1000L,
            category = "msg",
            isOngoing = false,
            now = now + 1000L
        )
        assertFalse("Duplicate notification must be rejected", addedDuplicate)
        assertEquals("Queue size should remain 1 after duplicate attempt", 1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testOngoingNotificationFiltering() {
        val added = NotificationCollectorService.enqueueNotification(
            packageName = "com.system.app",
            title = "System Update Running",
            content = "Downloading...",
            timestamp = 1000L,
            category = "sys",
            isOngoing = true
        )
        assertFalse("Ongoing notification must be filtered at ingestion", added)
        assertEquals(0, NotificationCollectorService.queueSize())
    }

    @Test
    fun testBackgroundCategoryFiltering() {
        val excludedCategories = listOf("progress", "navigation", "service", "sys", "system", "transport", "status")

        for (cat in excludedCategories) {
            val added = NotificationCollectorService.enqueueNotification(
                packageName = "com.test.background",
                title = "Background Alert",
                content = "Status update",
                timestamp = 1000L,
                category = cat,
                isOngoing = false
            )
            assertFalse("Category '$cat' must be excluded at ingestion", added)
        }

        assertEquals(0, NotificationCollectorService.queueSize())
    }

    @Test
    fun testNotificationRedactorPIISanitization() {
        val rawOtpText = "Your verification code is 882715 for login."
        val redactedOtp = NotificationRedactor.redact(rawOtpText)
        assertFalse(redactedOtp.contains("882715"))
        assertTrue(redactedOtp.contains("[REDACTED_OTP]"))

        val rawTokenText = "Session authorization bearer token=secretToken123456"
        val redactedToken = NotificationRedactor.redact(rawTokenText)
        assertFalse(redactedToken.contains("secretToken123456"))
        assertTrue(redactedToken.contains("[REDACTED_TOKEN]"))

        val rawEmailText = "Sender email address user.test@domain.com verified"
        val redactedEmail = NotificationRedactor.redact(rawEmailText)
        assertFalse(redactedEmail.contains("user.test@domain.com"))
        assertTrue(redactedEmail.contains("[REDACTED_EMAIL]"))
    }

    @Test
    fun testDrainQueueClearsState() {
        val now = System.currentTimeMillis()
        NotificationCollectorService.enqueueNotification("com.app1", "T1", "C1", now, "msg", false, now)
        NotificationCollectorService.enqueueNotification("com.app2", "T2", "C2", now + 1000L, "msg", false, now + 1000L)

        assertEquals(2, NotificationCollectorService.queueSize())
        val items = NotificationCollectorService.drainQueue(now + 1000L)
        assertEquals(2, items.size)
        assertEquals(0, NotificationCollectorService.queueSize())

        val addedAfterDrain = NotificationCollectorService.enqueueNotification("com.app1", "T1", "C1", now + 2000L, "msg", false, now + 2000L)
        assertTrue(addedAfterDrain)
    }

    @Test
    fun testHighThroughputPerformanceBenchmark() {
        val iterations = 1000
        val startTime = System.currentTimeMillis()

        for (i in 1..iterations) {
            val now = System.currentTimeMillis()
            NotificationCollectorService.enqueueNotification(
                packageName = "com.app.bench_$i",
                title = "Title $i",
                content = "Content $i",
                timestamp = now,
                category = "msg",
                isOngoing = false,
                now = now
            )
        }

        val elapsedTime = System.currentTimeMillis() - startTime
        assertTrue("Queue processing latency should be under 200ms (took ${elapsedTime}ms)", elapsedTime < 200)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize())
    }
}
