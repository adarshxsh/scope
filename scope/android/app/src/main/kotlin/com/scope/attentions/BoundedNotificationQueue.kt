package com.scope.attentions

/**
 * Thread-safe bounded FIFO queue with drop-oldest eviction policy.
 *
 * Enforces a configurable [maxCapacity] threshold (default 200 items).
 * When inserting a new item when full, the oldest entry (FIFO head)
 * is evicted automatically before adding the new entry.
 * Filters duplicate items matching package, title, and content.
 */
class BoundedNotificationQueue(
    maxCapacity: Int = DEFAULT_MAX_CAPACITY
) {
    companion object {
        const val DEFAULT_MAX_CAPACITY = 200
    }

    private val lock = Any()
    private val queue = ArrayDeque<NotificationData>()

    /** Configurable capacity threshold. Must be at least 1. */
    @Volatile
    var maxCapacity: Int = maxCapacity.coerceAtLeast(1)
        set(value) {
            val validValue = value.coerceAtLeast(1)
            synchronized(lock) {
                field = validValue
                while (queue.size > validValue) {
                    queue.removeFirst()
                }
            }
        }

    /** Returns current queue size. */
    val size: Int
        get() = synchronized(lock) { queue.size }

    /**
     * Offers a new [NotificationData] item to the queue.
     *
     * If an entry with identical [packageName], [title], and [content]
     * already exists, insertion is ignored and returns false.
     *
     * If the queue is at capacity, the oldest item is evicted prior to insertion.
     * Returns true if the item was added.
     */
    fun offer(data: NotificationData): Boolean {
        synchronized(lock) {
            val isDuplicate = queue.any {
                it.packageName == data.packageName &&
                        it.title == data.title &&
                        it.content == data.content
            }
            if (isDuplicate) {
                return false
            }

            while (queue.size >= maxCapacity && queue.isNotEmpty()) {
                queue.removeFirst()
            }

            queue.addLast(data)
            return true
        }
    }

    /**
     * Atomically extracts and clears all retained entries from the queue.
     */
    fun drain(): List<NotificationData> {
        synchronized(lock) {
            if (queue.isEmpty()) {
                return emptyList()
            }
            val result = ArrayList<NotificationData>(queue)
            queue.clear()
            return result
        }
    }

    /**
     * Clears all items from the queue.
     */
    fun clear() {
        synchronized(lock) {
            queue.clear()
        }
    }
}
