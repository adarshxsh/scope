package com.scope.attentions

import java.util.concurrent.ArrayBlockingQueue

/**
 * Thread-safe bounded queue with fixed maximum capacity (default 100).
 *
 * When capacity is reached, the oldest entry is automatically evicted (FIFO)
 * to prevent heap memory growth under high notification volume.
 */
open class BoundedNotificationQueue<T>(val capacity: Int = 100) {

    private val queue = ArrayBlockingQueue<T>(capacity)

    /**
     * Inserts [element] into the queue, evicting the oldest element
     * if maximum capacity has been reached.
     */
    @Synchronized
    fun add(element: T): Boolean {
        if (queue.size >= capacity) {
            queue.poll() // Evict oldest entry (FIFO)
        }
        return queue.offer(element)
    }

    /**
     * Alias for [add].
     */
    @Synchronized
    fun offer(element: T): Boolean {
        return add(element)
    }

    /**
     * Retrieves and removes the head of this queue, or null if empty.
     */
    @Synchronized
    fun poll(): T? {
        return queue.poll()
    }

    /**
     * Drains all elements from the queue atomically into a List.
     * The queue will be empty after this call.
     */
    @Synchronized
    fun drainQueue(): List<T> {
        val result = mutableListOf<T>()
        queue.drainTo(result)
        return result
    }

    /**
     * Current size of the queue.
     */
    val size: Int
        @Synchronized get() = queue.size

    /**
     * Returns true if queue is empty.
     */
    fun isEmpty(): Boolean {
        return size == 0
    }

    /**
     * Clears all items from the queue.
     */
    @Synchronized
    fun clear() {
        queue.clear()
    }

    /**
     * Returns true if at least one element matches the given [predicate].
     */
    @Synchronized
    fun any(predicate: (T) -> Boolean): Boolean {
        return queue.any(predicate)
    }
}

/**
 * Subclass alias for unit test compatibility.
 */
class BoundedQueue<T>(capacity: Int = 100) : BoundedNotificationQueue<T>(capacity)
