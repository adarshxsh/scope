package com.scope.attentions

import android.util.Log

/**
 * Thread-safe fixed-capacity ring buffer for storing [NotificationData].
 *
 * When maximum capacity is reached, adding a new item automatically evicts
 * the oldest un-drained notification in O(1) time complexity.
 *
 * References to evicted or drained items are immediately nulled out to prevent
 * memory leaks and allow prompt JVM garbage collection.
 */
class NotificationRingBuffer(val capacity: Int = 500) {

    init {
        require(capacity > 0) { "Capacity must be greater than 0" }
    }

    private val lock = Any()
    private val buffer = arrayOfNulls<NotificationData>(capacity)

    private var head = 0
    private var tail = 0
    private var currentSize = 0
    private var droppedCounter = 0L

    /**
     * Current number of notifications in the ring buffer.
     */
    val size: Int
        get() = synchronized(lock) { currentSize }

    /**
     * Total number of notifications evicted due to buffer overflow since creation or last clear.
     */
    val droppedCount: Long
        get() = synchronized(lock) { droppedCounter }

    /**
     * Adds a notification to the ring buffer in O(1) time complexity.
     * If full, evicts the oldest item (at head), increments [droppedCount],
     * and logs diagnostic drop counts.
     */
    fun add(data: NotificationData) {
        synchronized(lock) {
            if (currentSize == capacity) {
                // Buffer is full — evict oldest item at head
                buffer[head] = null
                head = (head + 1) % capacity
                currentSize--
                droppedCounter++

                if (droppedCounter == 1L || droppedCounter % 50L == 0L) {
                    logW(
                        TAG,
                        "Notification ring buffer full ($capacity). Evicted oldest notification. Total dropped: $droppedCounter"
                    )
                }
            }

            buffer[tail] = data
            tail = (tail + 1) % capacity
            currentSize++
        }
    }

    /**
     * Drains all notifications from the ring buffer in FIFO order and resets
     * the buffer size to 0.
     */
    fun drain(): List<NotificationData> {
        synchronized(lock) {
            if (currentSize == 0) {
                return emptyList()
            }

            val result = ArrayList<NotificationData>(currentSize)
            for (i in 0 until currentSize) {
                val idx = (head + i) % capacity
                val item = buffer[idx]
                if (item != null) {
                    result.add(item)
                    buffer[idx] = null
                }
            }

            head = 0
            tail = 0
            currentSize = 0

            return result
        }
    }

    /**
     * Resets the ring buffer state and drop counter.
     */
    fun clear() {
        synchronized(lock) {
            for (i in 0 until capacity) {
                buffer[i] = null
            }
            head = 0
            tail = 0
            currentSize = 0
            droppedCounter = 0L
        }
    }

    private fun logW(tag: String, msg: String) {
        try {
            Log.w(tag, msg)
        } catch (_: Throwable) {
            // Unmocked android.util.Log during standalone JVM unit tests
        }
    }

    companion object {
        private const val TAG = "NotifRingBuffer"
    }
}
