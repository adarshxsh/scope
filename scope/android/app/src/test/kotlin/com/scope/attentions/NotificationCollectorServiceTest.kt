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
    fun testQueueBoundingAndDropOldestEviction() {
        val totalToInsert = 300
        for (i in 1..totalToInsert) {
            val added = NotificationCollectorService.enqueueNotification(
                packageName = "com.test.app$i",
                title = "Title $i",
                content = "Content $i",
                timestamp = System.currentTimeMillis() + i,
                category = "msg",
                isOngoing = false
            )
            assertTrue("Item $i should be added", added)
        }

        // Queue size must be capped at MAX_QUEUE_SIZE (250)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, drained.size)

        // Verify drop-oldest: oldest 50 items (1..50) were evicted, so first item in drained queue is 51
        assertEquals("com.test.app51", drained.first().packageName)
        assertEquals("com.test.app300", drained.last().packageName)
    }

    @Test
    fun testO1Deduplication() {
        val addedFirst = NotificationCollectorService.enqueueNotification(
            packageName = "com.example.chat",
            title = "New Message",
            content = "Hello there",
            timestamp = 1000L,
            category = "msg",
            isOngoing = false
        )
        assertTrue(addedFirst)
        assertEquals(1, NotificationCollectorService.queueSize())

        // Duplicate with same package, title, content
        val addedDuplicate = NotificationCollectorService.enqueueNotification(
            packageName = "com.example.chat",
            title = "New Message",
            content = "Hello there",
            timestamp = 2000L,
            category = "msg",
            isOngoing = false
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
        NotificationCollectorService.enqueueNotification("com.app1", "T1", "C1", 1000L, "msg", false)
        NotificationCollectorService.enqueueNotification("com.app2", "T2", "C2", 2000L, "msg", false)

        assertEquals(2, NotificationCollectorService.queueSize())
        val items = NotificationCollectorService.drainQueue()
        assertEquals(2, items.size)
        assertEquals(0, NotificationCollectorService.queueSize())

        // Re-adding item after drain should work as dedupSet was cleared
        val addedAfterDrain = NotificationCollectorService.enqueueNotification("com.app1", "T1", "C1", 3000L, "msg", false)
        assertTrue(addedAfterDrain)
    }

    @Test
    fun testHighThroughputPerformanceBenchmark() {
        val iterations = 1000
        val startTime = System.currentTimeMillis()

        for (i in 1..iterations) {
            NotificationCollectorService.enqueueNotification(
                packageName = "com.app.bench_$i",
                title = "Title $i",
                content = "Content $i",
                timestamp = System.currentTimeMillis(),
                category = "msg",
                isOngoing = false
            )
        }

        val elapsedTime = System.currentTimeMillis() - startTime
        // Benchmark requirement: sub-50ms latency for batch queue processing
        assertTrue("Queue processing latency should be under 50ms (took ${elapsedTime}ms)", elapsedTime < 50)
        assertEquals(NotificationCollectorService.MAX_QUEUE_SIZE, NotificationCollectorService.queueSize())
    }
}
