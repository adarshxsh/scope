package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.clearQueue()
        NotificationCollectorService.maxCapacity = NotificationCollectorService.DEFAULT_MAX_CAPACITY
    }

    @Test
    fun defaultCapacityIs200() {
        assertEquals(200, NotificationCollectorService.DEFAULT_MAX_CAPACITY)
        assertEquals(200, NotificationCollectorService.maxCapacity)
        assertEquals(0, NotificationCollectorService.queueSize())
    }

    @Test
    fun insert500NotificationsRetains200MostRecentAndDrops300Oldest() {
        val queue = BoundedNotificationQueue(200)

        // Insert 500 distinct notifications
        for (i in 1..500) {
            val notification = NotificationData(
                id = "notif_$i",
                packageName = "com.example.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = System.currentTimeMillis() + i,
                category = "msg",
                isOngoing = false
            )
            val added = queue.offer(notification)
            assertTrue("Expected item $i to be added", added)
        }

        // Verify queue size is capped at 200
        assertEquals(200, queue.size)

        // Drain the queue and inspect retained items
        val drained = queue.drain()
        assertEquals(200, drained.size)

        // Oldest 300 (1..300) should be dropped; 301..500 must be retained in FIFO order
        assertEquals("notif_301", drained.first().id)
        assertEquals("Title 301", drained.first().title)

        assertEquals("notif_500", drained.last().id)
        assertEquals("Title 500", drained.last().title)

        for (idx in drained.indices) {
            val expectedNumber = 301 + idx
            assertEquals("notif_$expectedNumber", drained[idx].id)
            assertEquals("Title $expectedNumber", drained[idx].title)
        }
    }

    @Test
    fun configurableCapacityThreshold() {
        val queue = BoundedNotificationQueue(10)
        assertEquals(10, queue.maxCapacity)

        for (i in 1..20) {
            queue.offer(
                NotificationData(
                    id = "notif_$i",
                    packageName = "com.example.app",
                    title = "Title $i",
                    content = "Content $i",
                    timestamp = System.currentTimeMillis() + i,
                    category = null,
                    isOngoing = false
                )
            )
        }

        assertEquals(10, queue.size)
        var drained = queue.drain()
        assertEquals(10, drained.size)
        assertEquals("notif_11", drained.first().id)
        assertEquals("notif_20", drained.last().id)

        // Test reducing capacity dynamically
        queue.maxCapacity = 5
        for (i in 1..10) {
            queue.offer(
                NotificationData(
                    id = "notif_$i",
                    packageName = "com.example.app",
                    title = "Title $i",
                    content = "Content $i",
                    timestamp = System.currentTimeMillis() + i,
                    category = null,
                    isOngoing = false
                )
            )
        }
        assertEquals(5, queue.size)
        drained = queue.drain()
        assertEquals(5, drained.size)
        assertEquals("notif_6", drained.first().id)
        assertEquals("notif_10", drained.last().id)
    }

    @Test
    fun duplicateNotificationFiltering() {
        val queue = BoundedNotificationQueue(200)

        val notif1 = NotificationData(
            id = "notif_1",
            packageName = "com.chat.app",
            title = "New Message",
            content = "Hello there",
            timestamp = 1000L,
            category = "msg",
            isOngoing = false
        )

        val notifDuplicate = NotificationData(
            id = "notif_2",
            packageName = "com.chat.app",
            title = "New Message",
            content = "Hello there",
            timestamp = 2000L,
            category = "msg",
            isOngoing = false
        )

        val notifDifferentContent = NotificationData(
            id = "notif_3",
            packageName = "com.chat.app",
            title = "New Message",
            content = "How are you?",
            timestamp = 3000L,
            category = "msg",
            isOngoing = false
        )

        assertTrue(queue.offer(notif1))
        assertFalse(queue.offer(notifDuplicate))
        assertTrue(queue.offer(notifDifferentContent))

        assertEquals(2, queue.size)
        val drained = queue.drain()
        assertEquals(2, drained.size)
        assertEquals("notif_1", drained[0].id)
        assertEquals("notif_3", drained[1].id)
    }

    @Test
    fun atomicDrainQueue() {
        val queue = BoundedNotificationQueue(200)

        for (i in 1..50) {
            queue.offer(
                NotificationData(
                    id = "notif_$i",
                    packageName = "com.app",
                    title = "Title $i",
                    content = "Text $i",
                    timestamp = i.toLong(),
                    category = null,
                    isOngoing = false
                )
            )
        }

        assertEquals(50, queue.size)

        val firstDrain = queue.drain()
        assertEquals(50, firstDrain.size)
        assertEquals(0, queue.size)

        val secondDrain = queue.drain()
        assertTrue(secondDrain.isEmpty())
        assertEquals(0, queue.size)
    }

    @Test
    fun threadSafetyUnderHighConcurrency() {
        val queue = BoundedNotificationQueue(200)
        val threadCount = 10
        val itemsPerThread = 100
        val executor = Executors.newFixedThreadPool(threadCount + 2)

        for (t in 0 until threadCount) {
            executor.submit {
                for (i in 0 until itemsPerThread) {
                    val id = t * itemsPerThread + i
                    queue.offer(
                        NotificationData(
                            id = "notif_$id",
                            packageName = "com.pkg.$t",
                            title = "Title $id",
                            content = "Content $id",
                            timestamp = System.currentTimeMillis(),
                            category = null,
                            isOngoing = false
                        )
                    )
                }
            }
        }

        // Concurrent drainer thread
        executor.submit {
            for (i in 0 until 50) {
                queue.drain()
                Thread.sleep(1)
            }
        }

        executor.shutdown()
        val finished = executor.awaitTermination(5, TimeUnit.SECONDS)
        assertTrue("Concurrent execution completed in time", finished)
        assertTrue("Queue size must be <= 200", queue.size <= 200)
    }

    @Test
    fun memoryStressSequence10kNotifications() {
        val queue = BoundedNotificationQueue(200)

        // Force GC before starting baseline measurement
        System.gc()
        val baselineMemory = Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()

        // 10,000 notification stress sequence
        for (i in 1..10000) {
            queue.offer(
                NotificationData(
                    id = "notif_$i",
                    packageName = "com.stress.app.${i % 100}",
                    title = "Stress Test Title $i",
                    content = "Stress Test Payload Content Body $i",
                    timestamp = System.currentTimeMillis(),
                    category = "promo",
                    isOngoing = false
                )
            )
        }

        assertEquals(200, queue.size)

        System.gc()
        val postStressMemory = Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()
        val deltaMemoryBytes = postStressMemory - baselineMemory

        // Total memory delta should stay well under 1MB (1,048,576 bytes)
        assertTrue(
            "Memory growth ($deltaMemoryBytes bytes) must remain under 1MB",
            deltaMemoryBytes < 1_048_576
        )

        val drained = queue.drain()
        assertEquals(200, drained.size)
        assertEquals("notif_9801", drained.first().id)
        assertEquals("notif_10000", drained.last().id)
    }
}
