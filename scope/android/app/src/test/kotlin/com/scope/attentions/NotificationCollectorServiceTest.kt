package com.scope.attentions

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.resetForTest()
    }

    @Test
    fun testQueueBoundedAt250AndEviction() {
        // Enqueue 300 unique notifications
        for (i in 1..300) {
            val added = NotificationCollectorService.addNotification(
                packageName = "com.example.app$i",
                title = "Title $i",
                content = "Content $i"
            )
            assertTrue("Item $i should be added", added)
            assertTrue("Queue size should never exceed 250", NotificationCollectorService.queueSize() <= 250)
        }

        assertEquals("Queue size should be capped at 250", 250, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(250, drained.size)

        // The oldest 50 items (1..50) should have been evicted.
        // So the first item in the drained queue should be item 51.
        assertEquals("com.example.app51", drained.first().packageName)
        assertEquals("Title 51", drained.first().title)
        assertEquals("com.example.app300", drained.last().packageName)
        assertEquals("Title 300", drained.last().title)

        // Verifying evicted deduplication keys:
        // Item 1 was evicted, so re-adding item 1 should now succeed
        val reAddedItem1 = NotificationCollectorService.addNotification(
            packageName = "com.example.app1",
            title = "Title 1",
            content = "Content 1"
        )
        assertTrue("Evicted key should be cleared from dedupSet allowing re-addition", reAddedItem1)
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testDeduplicationO1() {
        val addedFirst = NotificationCollectorService.addNotification(
            packageName = "com.test.app",
            title = "Alert",
            content = "Message Body"
        )
        assertTrue("First insertion should succeed", addedFirst)
        assertEquals(1, NotificationCollectorService.queueSize())

        // Duplicate insertion
        val addedDuplicate = NotificationCollectorService.addNotification(
            packageName = "com.test.app",
            title = "Alert",
            content = "Message Body"
        )
        assertFalse("Duplicate notification should be rejected", addedDuplicate)
        assertEquals(1, NotificationCollectorService.queueSize())

        // Different title -> non-duplicate
        val addedDifferentTitle = NotificationCollectorService.addNotification(
            packageName = "com.test.app",
            title = "Alert 2",
            content = "Message Body"
        )
        assertTrue("Different title notification should be accepted", addedDifferentTitle)
        assertEquals(2, NotificationCollectorService.queueSize())
    }

    @Test
    fun testDrainQueueClearsQueueAndDedupSet() {
        NotificationCollectorService.addNotification("com.app", "Title 1", "Body 1")
        NotificationCollectorService.addNotification("com.app", "Title 2", "Body 2")
        assertEquals(2, NotificationCollectorService.queueSize())

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(2, drained.size)
        assertEquals(0, NotificationCollectorService.queueSize())

        // Re-adding drained items should succeed because dedupSet was cleared
        val reAdded = NotificationCollectorService.addNotification("com.app", "Title 1", "Body 1")
        assertTrue("Re-adding after drain should succeed as dedup set is cleared", reAdded)
        assertEquals(1, NotificationCollectorService.queueSize())
    }

    @Test
    fun testAtomicIdCounterAndConcurrentAdditions() {
        val threadCount = 10
        val itemsPerThread = 20
        val executor = Executors.newFixedThreadPool(threadCount)

        for (t in 0 until threadCount) {
            executor.submit {
                for (i in 0 until itemsPerThread) {
                    NotificationCollectorService.addNotification(
                        packageName = "com.thread.$t",
                        title = "Title $i",
                        content = "Content $i"
                    )
                }
            }
        }

        executor.shutdown()
        assertTrue("Threads should complete within 5 seconds", executor.awaitTermination(5, TimeUnit.SECONDS))

        val drained = NotificationCollectorService.drainQueue()
        assertEquals(threadCount * itemsPerThread, drained.size)

        // Ensure 100% unique notification IDs generated under concurrent execution
        val uniqueIds = drained.map { it.id }.toSet()
        assertEquals("All generated notification IDs must be unique", drained.size, uniqueIds.size)
    }

    @Test
    fun testConcurrentAddAndDrain() {
        val threadCount = 8
        val executor = Executors.newFixedThreadPool(threadCount)

        for (t in 0 until threadCount) {
            if (t % 2 == 0) {
                executor.submit {
                    for (i in 0..100) {
                        NotificationCollectorService.addNotification(
                            packageName = "com.concurrent.$t",
                            title = "Title $i",
                            content = "Content $i"
                        )
                    }
                }
            } else {
                executor.submit {
                    for (i in 0..50) {
                        NotificationCollectorService.drainQueue()
                        Thread.yield()
                    }
                }
            }
        }

        executor.shutdown()
        assertTrue("Concurrent add/drain should finish safely without exceptions", executor.awaitTermination(5, TimeUnit.SECONDS))
    }
}
