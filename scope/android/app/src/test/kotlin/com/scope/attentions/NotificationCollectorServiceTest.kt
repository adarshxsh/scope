package com.scope.attentions

import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.clearQueue()
    }

    private fun createNotification(
        id: String,
        packageName: String = "com.example.app",
        title: String = "Test Title",
        content: String = "Test Content",
        timestamp: Long = System.currentTimeMillis()
    ): NotificationData {
        return NotificationData(
            id = id,
            packageName = packageName,
            title = title,
            content = content,
            timestamp = timestamp,
            category = "msg",
            isOngoing = false
        )
    }

    @Test
    fun testHardLimitCapacity200() {
        assertEquals(0, NotificationCollectorService.queueSize())

        for (i in 0 until 250) {
            val notif = createNotification(
                id = "notif_$i",
                packageName = "com.app.$i",
                title = "Title $i",
                content = "Content $i"
            )
            NotificationCollectorService.addNotification(notif)
        }

        assertEquals(200, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(200, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())

        // The first 50 items (0..49) should have been evicted.
        // The drained list should start from item 50 ("com.app.50").
        assertEquals("com.app.50", drained.first().packageName)
        assertEquals("com.app.249", drained.last().packageName)
    }

    @Test
    fun testFifoEviction() {
        // Fill queue to capacity (200 items: 0..199)
        for (i in 0 until 200) {
            NotificationCollectorService.addNotification(
                createNotification(id = "id_$i", title = "Title $i", content = "Body $i")
            )
        }

        assertEquals(200, NotificationCollectorService.queueSize())

        // Adding 201st item should evict oldest item ("Title 0", "Body 0")
        val added = NotificationCollectorService.addNotification(
            createNotification(id = "id_200", title = "Title 200", content = "Body 200")
        )
        assertTrue(added)
        assertEquals(200, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals("Title 1", drained.first().title)
        assertEquals("Title 200", drained.last().title)
    }

    @Test
    fun testConstantTimeDeduplication() {
        val notif1 = createNotification(id = "1", packageName = "com.test", title = "Alert", content = "Msg")
        val notif2 = createNotification(id = "2", packageName = "com.test", title = "Alert", content = "Msg")

        assertTrue(NotificationCollectorService.addNotification(notif1))
        assertFalse("Duplicate notification should be rejected", NotificationCollectorService.addNotification(notif2))
        assertEquals(1, NotificationCollectorService.queueSize())

        // Different package name should be accepted
        val notif3 = createNotification(id = "3", packageName = "com.other", title = "Alert", content = "Msg")
        assertTrue(NotificationCollectorService.addNotification(notif3))

        // Different content should be accepted
        val notif4 = createNotification(id = "4", packageName = "com.test", title = "Alert", content = "New Msg")
        assertTrue(NotificationCollectorService.addNotification(notif4))

        assertEquals(3, NotificationCollectorService.queueSize())
    }

    @Test
    fun testReAddAfterEviction() {
        val notif0 = createNotification(id = "0", packageName = "com.app.0", title = "Title 0", content = "Body 0")
        assertTrue(NotificationCollectorService.addNotification(notif0))

        // Add 200 distinct items to cause eviction of notif0
        for (i in 1..200) {
            NotificationCollectorService.addNotification(
                createNotification(id = "id_$i", packageName = "com.app.$i", title = "Title $i", content = "Body $i")
            )
        }

        assertEquals(200, NotificationCollectorService.queueSize())

        // Since notif0 was evicted, its key should be removed from deduplication index
        val reAddNotif0 = createNotification(id = "readd_0", packageName = "com.app.0", title = "Title 0", content = "Body 0")
        assertTrue("Evicted notification key should be re-addable", NotificationCollectorService.addNotification(reAddNotif0))
        assertEquals(200, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals("com.app.2", drained.first().packageName)
        assertEquals("com.app.0", drained.last().packageName)
    }

    @Test
    fun testAtomicDrainResetsQueueAndIndex() {
        val notif = createNotification(id = "1", packageName = "com.app", title = "Hello", content = "World")
        assertTrue(NotificationCollectorService.addNotification(notif))
        assertEquals(1, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(1, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())

        // Re-adding same notification after drain should succeed because dedup index was cleared
        assertTrue(NotificationCollectorService.addNotification(notif))
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testThreadSafetyAndConcurrency() {
        val threadCount = 10
        val itemsPerThread = 100
        val executor = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)

        for (t in 0 until threadCount) {
            executor.execute {
                try {
                    for (i in 0 until itemsPerThread) {
                        val notif = createNotification(
                            id = "t${t}_$i",
                            packageName = "com.thread.$t",
                            title = "Title $i",
                            content = "Content $i"
                        )
                        NotificationCollectorService.addNotification(notif)
                        if (i % 25 == 0) {
                            NotificationCollectorService.queueSize()
                        }
                    }
                } finally {
                    latch.countDown()
                }
            }
        }

        latch.await()
        executor.shutdown()

        val size = NotificationCollectorService.queueSize()
        assertTrue("Queue size should never exceed 200", size <= 200)

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(size, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())
    }
}
