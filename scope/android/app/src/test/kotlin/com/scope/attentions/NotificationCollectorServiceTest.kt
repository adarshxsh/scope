package com.scope.attentions

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

fun main() {
    val test = NotificationCollectorServiceTest()
    test.testQueueCapacityCeilingAndFifoEviction()
    test.testAtomicIdGenerationAndUniquenessUnderConcurrency()
    test.testDeduplicationRejection()
    test.testDrainQueuePurgesQueueAndDeduplicationSet()
    println("ALL KOTLIN NOTIFICATION QUEUE TESTS PASSED SUCCESSFULLY!")
}

class NotificationCollectorServiceTest {

    private fun setUp() {
        NotificationCollectorService.clearQueue()
    }

    fun testQueueCapacityCeilingAndFifoEviction() {
        setUp()
        // Add 550 notifications
        for (i in 1..550) {
            val added = NotificationCollectorService.addNotification(
                packageName = "com.test.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = i.toLong()
            )
            assert(added) { "Failed to add item $i" }
        }

        // Hard ceiling check
        val currentSize = NotificationCollectorService.queueSize()
        assert(currentSize == 500) { "Expected queue size 500 but was $currentSize" }
        assert(NotificationCollectorService.deduplicationSetSize() == 500) {
            "Expected dedup set size 500 but was ${NotificationCollectorService.deduplicationSetSize()}"
        }

        // Check FIFO eviction: the first 50 items (1..50) should have been evicted
        val items = NotificationCollectorService.drainQueue()
        assert(items.size == 500) { "Expected 500 drained items" }
        assert(items.first().title == "Title 51") { "Expected first item to be Title 51, got ${items.first().title}" }
        assert(items.last().title == "Title 550") { "Expected last item to be Title 550, got ${items.last().title}" }
        println("✓ testQueueCapacityCeilingAndFifoEviction passed")
    }

    fun testAtomicIdGenerationAndUniquenessUnderConcurrency() {
        setUp()
        val threadCount = 10
        val itemsPerThread = 50
        val executor = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)

        for (t in 0 until threadCount) {
            executor.submit {
                try {
                    for (i in 0 until itemsPerThread) {
                        NotificationCollectorService.addNotification(
                            packageName = "com.concurrent.app$t",
                            title = "Title $i from thread $t",
                            content = "Content $i",
                            timestamp = System.currentTimeMillis()
                        )
                    }
                } finally {
                    latch.countDown()
                }
            }
        }

        val completed = latch.await(10, TimeUnit.SECONDS)
        executor.shutdown()
        assert(completed) { "Concurrent test timed out" }

        val items = NotificationCollectorService.drainQueue()
        val totalExpected = threadCount * itemsPerThread
        assert(items.size == totalExpected) { "Expected $totalExpected items, got ${items.size}" }

        val ids = items.map { it.id }.toSet()
        assert(ids.size == totalExpected) { "Expected $totalExpected unique IDs, got ${ids.size}" }
        println("✓ testAtomicIdGenerationAndUniquenessUnderConcurrency passed")
    }

    fun testDeduplicationRejection() {
        setUp()
        val addedFirst = NotificationCollectorService.addNotification(
            packageName = "com.example.chat",
            title = "Alice",
            content = "Hello there",
            timestamp = 1000L
        )
        assert(addedFirst) { "First notification should be added" }

        val addedDuplicate = NotificationCollectorService.addNotification(
            packageName = "com.example.chat",
            title = "Alice",
            content = "Hello there",
            timestamp = 2000L
        )
        assert(!addedDuplicate) { "Duplicate notification should be rejected" }

        assert(NotificationCollectorService.queueSize() == 1) { "Queue size should remain 1" }
        assert(NotificationCollectorService.deduplicationSetSize() == 1) { "Dedup set size should remain 1" }
        println("✓ testDeduplicationRejection passed")
    }

    fun testDrainQueuePurgesQueueAndDeduplicationSet() {
        setUp()
        for (i in 1..10) {
            NotificationCollectorService.addNotification(
                packageName = "com.test.app",
                title = "Title $i",
                content = "Content $i",
                timestamp = i.toLong()
            )
        }

        assert(NotificationCollectorService.queueSize() == 10)
        assert(NotificationCollectorService.deduplicationSetSize() == 10)

        val drained = NotificationCollectorService.drainQueue()
        assert(drained.size == 10)
        assert(NotificationCollectorService.queueSize() == 0) { "Queue size should be 0 after drain" }
        assert(NotificationCollectorService.deduplicationSetSize() == 0) { "Dedup set size should be 0 after drain" }
        println("✓ testDrainQueuePurgesQueueAndDeduplicationSet passed")
    }
}
