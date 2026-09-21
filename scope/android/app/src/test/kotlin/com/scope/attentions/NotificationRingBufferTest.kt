package com.scope.attentions

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

class NotificationRingBufferTest {

    private fun createNotif(id: String): NotificationData {
        return NotificationData(
            id = id,
            packageName = "com.example.app",
            title = "Title $id",
            content = "Content $id",
            timestamp = System.currentTimeMillis(),
            category = "msg",
            isOngoing = false
        )
    }

    @Test
    fun testCapacityEnforcement() {
        val buffer = NotificationRingBuffer(500)
        assertEquals(0, buffer.size)
        assertEquals(0L, buffer.droppedCount)

        for (i in 1..500) {
            buffer.add(createNotif("notif_$i"))
        }

        assertEquals(500, buffer.size)
        assertEquals(0L, buffer.droppedCount)
    }

    @Test
    fun testEvictionOnOverflow() {
        val buffer = NotificationRingBuffer(500)

        // Push 501 items
        for (i in 1..501) {
            buffer.add(createNotif("notif_$i"))
        }

        // Capacity is 500, item 1 should be evicted
        assertEquals(500, buffer.size)
        assertEquals(1L, buffer.droppedCount)

        val drained = buffer.drain()
        assertEquals(500, drained.size)
        assertEquals(0, buffer.size)

        // First item should be item 2, last item should be item 501
        assertEquals("notif_2", drained.first().id)
        assertEquals("notif_501", drained.last().id)
    }

    @Test
    fun testSmallCapacityEviction() {
        val buffer = NotificationRingBuffer(3)

        for (i in 1..5) {
            buffer.add(createNotif("item_$i"))
        }

        assertEquals(3, buffer.size)
        assertEquals(2L, buffer.droppedCount)

        val drained = buffer.drain()
        assertEquals(3, drained.size)
        assertEquals("item_3", drained[0].id)
        assertEquals("item_4", drained[1].id)
        assertEquals("item_5", drained[2].id)

        assertEquals(0, buffer.size)
    }

    @Test
    fun testDrainResetsSize() {
        val buffer = NotificationRingBuffer(10)

        assertTrue(buffer.drain().isEmpty())
        assertEquals(0, buffer.size)

        for (i in 1..5) {
            buffer.add(createNotif("item_$i"))
        }
        assertEquals(5, buffer.size)

        val drained = buffer.drain()
        assertEquals(5, drained.size)
        assertEquals(0, buffer.size)

        // Draining again returns empty
        assertTrue(buffer.drain().isEmpty())
    }

    @Test
    fun testFifoOrderWithMultipleWraps() {
        val buffer = NotificationRingBuffer(5)

        // Push 12 items into capacity 5
        for (i in 1..12) {
            buffer.add(createNotif("id_$i"))
        }

        assertEquals(5, buffer.size)
        assertEquals(7L, buffer.droppedCount)

        val drained = buffer.drain()
        assertEquals(5, drained.size)
        val expectedIds = listOf("id_8", "id_9", "id_10", "id_11", "id_12")
        val actualIds = drained.map { it.id }
        assertEquals(expectedIds, actualIds)
    }

    @Test
    fun testConcurrentOperations() {
        val capacity = 100
        val buffer = NotificationRingBuffer(capacity)
        val numThreads = 8
        val itemsPerThread = 2000
        val totalExpectedAdditions = numThreads * itemsPerThread

        val executor = Executors.newFixedThreadPool(numThreads + 2)
        val totalDrainedCount = AtomicLong(0)

        // Producer tasks
        for (t in 0 until numThreads) {
            executor.submit {
                for (i in 1..itemsPerThread) {
                    buffer.add(createNotif("t${t}_$i"))
                }
            }
        }

        // Consumer tasks draining concurrently
        for (c in 0..1) {
            executor.submit {
                for (i in 1..50) {
                    val items = buffer.drain()
                    totalDrainedCount.addAndGet(items.size.toLong())
                    Thread.sleep(1)
                }
            }
        }

        executor.shutdown()
        assertTrue(executor.awaitTermination(10, TimeUnit.SECONDS))

        // Drain any remaining items in buffer
        val finalDrain = buffer.drain()
        totalDrainedCount.addAndGet(finalDrain.size.toLong())

        val totalProcessed = totalDrainedCount.get() + buffer.droppedCount
        assertEquals(totalExpectedAdditions.toLong(), totalProcessed)
        assertEquals(0, buffer.size)
    }

    @Test
    fun testClear() {
        val buffer = NotificationRingBuffer(10)
        for (i in 1..15) {
            buffer.add(createNotif("item_$i"))
        }
        assertEquals(10, buffer.size)
        assertEquals(5L, buffer.droppedCount)

        buffer.clear()
        assertEquals(0, buffer.size)
        assertEquals(0L, buffer.droppedCount)
        assertTrue(buffer.drain().isEmpty())
    }
}
