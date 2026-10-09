package com.scope.attentions

/**
 * Thread-safe bounded FIFO queue with drop-oldest eviction policy and TTL pruning.
 *
 * Enforces a configurable [maxCapacity] threshold (default 100 items)
 * and [maxAgeMs] time-to-live threshold (default 15 minutes).
 * When inserting a new item when full, the oldest entry (FIFO head)
 * is evicted automatically before adding the new entry.
 * Filters duplicate items matching package, title, and content.
 */
class BoundedNotificationQueue(
    maxCapacity: Int = DEFAULT_MAX_CAPACITY,
    @Volatile var maxAgeMs: Long = DEFAULT_MAX_AGE_MS
) {
    companion object {
        const val DEFAULT_MAX_CAPACITY = 100
        const val DEFAULT_MAX_AGE_MS = 15 * 60 * 1000L
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
     * Removes entries older than [maxAgeMs] relative to [now].
     */
    fun pruneExpired(now: Long = System.currentTimeMillis()) {
        synchronized(lock) {
            queue.removeAll { now - it.timestamp > maxAgeMs }
        }
    }

    /**
     * Offers a new [NotificationData] item to the queue.
     *
     * Prunes expired items first. If the item itself is expired relative to [now], insertion is rejected.
     * If an entry with identical [packageName], [title], and [content] already exists, insertion is ignored.
     * If the queue is at capacity, the oldest item is evicted prior to insertion.
     * Returns true if the item was added.
     */
    fun offer(data: NotificationData, now: Long = System.currentTimeMillis()): Boolean {
        synchronized(lock) {
            pruneExpired(now)

            if (now - data.timestamp > maxAgeMs) {
                return false
            }

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
     * Atomically extracts and clears all retained non-expired entries from the queue.
     */
    fun drain(now: Long = System.currentTimeMillis()): List<NotificationData> {
        synchronized(lock) {
            if (queue.isEmpty()) {
                return emptyList()
            }
            val result = ArrayList<NotificationData>()
            while (queue.isNotEmpty()) {
                val item = queue.removeFirst()
                if (now - item.timestamp <= maxAgeMs) {
                    result.add(item)
                }
            }
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
