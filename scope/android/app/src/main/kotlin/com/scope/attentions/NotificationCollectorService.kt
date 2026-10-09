package com.scope.attentions

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.security.MessageDigest
import java.util.ArrayDeque
import java.util.HashSet
import java.util.concurrent.atomic.AtomicLong

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are placed in a static FIFO queue capped at [MAX_QUEUE_SIZE]
 * with drop-oldest eviction, TTL expiration ([MAX_AGE_MS]), thread-safe ID generation,
 * and O(1) deduplication.
 * The queue is drained by [MainActivity] when Flutter requests them via MethodChannel.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Maximum allowed queue size to prevent unbounded memory growth. */
        const val MAX_QUEUE_SIZE = 100

        /** Maximum time-to-live for queued notifications (15 minutes in milliseconds). */
        const val MAX_AGE_MS = 15 * 60 * 1000L

        /** Excluded background and system status categories. */
        private val EXCLUDED_CATEGORIES = setOf(
            "progress", "navigation", "service", "sys", "system", "transport", "status"
        )

        private val lock = Any()

        /** Synchronized FIFO queue of captured notifications. */
        private val queue = ArrayDeque<NotificationData>()

        /** O(1) deduplication set tracking "packageName:title:content". */
        private val dedupSet = HashSet<String>()

        /** Thread-safe counter for generating unique IDs within a session. */
        private val idCounter = AtomicLong(0L)

        private fun getDedupKey(packageName: String, title: String, content: String): String {
            return "$packageName:$title:$content"
        }

        /**
         * Removes entries older than [MAX_AGE_MS] from the queue.
         */
        fun pruneExpired(now: Long = System.currentTimeMillis()) {
            synchronized(lock) {
                val iterator = queue.iterator()
                while (iterator.hasNext()) {
                    val item = iterator.next()
                    if (now - item.timestamp > MAX_AGE_MS) {
                        iterator.remove()
                        dedupSet.remove(getDedupKey(item.packageName, item.title, item.content))
                    }
                }
            }
        }

        /**
         * Adds a [NotificationData] item to the queue after pruning expired items
         * and enforcing maximum queue capacity.
         */
        fun addNotification(data: NotificationData, now: Long = System.currentTimeMillis()) {
            synchronized(lock) {
                pruneExpired(now)

                // Do not add item if it is already expired relative to current time
                if (now - data.timestamp > MAX_AGE_MS) {
                    return
                }

                // Filter out ongoing notifications
                if (data.isOngoing) {
                    return
                }

                // Filter out background and system status categories
                if (data.category != null && EXCLUDED_CATEGORIES.contains(data.category.lowercase())) {
                    return
                }

                val key = getDedupKey(data.packageName, data.title, data.content)
                if (dedupSet.contains(key)) {
                    return
                }

                // Evict oldest notification if queue reaches MAX_QUEUE_SIZE before adding new items
                while (queue.size >= MAX_QUEUE_SIZE) {
                    val evicted = queue.removeFirst()
                    val evictedKey = getDedupKey(evicted.packageName, evicted.title, evicted.content)
                    dedupSet.remove(evictedKey)
                }

                queue.addLast(data)
                dedupSet.add(key)
            }
        }

        /**
         * Enqueues a notification into the bounded queue if it passes filters and deduplication.
         * Returns true if successfully added, false if skipped or deduplicated.
         */
        fun enqueueNotification(
            packageName: String,
            title: String,
            content: String,
            timestamp: Long,
            category: String?,
            isOngoing: Boolean,
            now: Long = timestamp
        ): Boolean {
            synchronized(lock) {
                // Skips ongoing/persistent notifications
                if (isOngoing) {
                    return false
                }

                // Skips background and system status categories
                if (category != null && EXCLUDED_CATEGORIES.contains(category.lowercase())) {
                    return false
                }

                val key = getDedupKey(packageName, title, content)
                if (dedupSet.contains(key)) {
                    return false
                }

                val data = NotificationData(
                    id = "notif_${idCounter.incrementAndGet()}",
                    packageName = packageName,
                    title = title,
                    content = content,
                    timestamp = timestamp,
                    category = category,
                    isOngoing = isOngoing
                )

                addNotification(data, now)
                return dedupSet.contains(key)
            }
        }

        /**
         * Drains all non-expired notifications from the queue and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue and deduplication set are empty.
         */
        fun drainQueue(now: Long = System.currentTimeMillis()): List<NotificationData> {
            synchronized(lock) {
                val result = mutableListOf<NotificationData>()
                while (!queue.isEmpty()) {
                    val item = queue.removeFirst()
                    if (now - item.timestamp <= MAX_AGE_MS) {
                        result.add(item)
                    }
                }
                dedupSet.clear()
                return result
            }
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int {
            synchronized(lock) {
                return queue.size
            }
        }

        /**
         * Clears the queue and deduplication set (primarily for testing/reset).
         */
        fun clearQueue() {
            synchronized(lock) {
                queue.clear()
                dedupSet.clear()
                idCounter.set(0L)
            }
        }

        /**
         * Resets the ID counter (primarily for testing).
         */
        fun resetIdCounter() {
            idCounter.set(0L)
        }

        private fun hashString(input: String): String {
            return try {
                val digest = MessageDigest.getInstance("SHA-256")
                val hash = digest.digest(input.toByteArray(Charsets.UTF_8))
                hash.take(4).joinToString("") { "%02x".format(it) }
            } catch (e: Exception) {
                "anonymized"
            }
        }
    }

    private fun addSbnToQueue(sbn: StatusBarNotification, now: Long = System.currentTimeMillis()) {
        try {
            val notification = sbn.notification ?: return
            val extras = notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing || ((notification.flags and Notification.FLAG_ONGOING_EVENT) != 0)
            val packageName = sbn.packageName ?: "unknown"
            val category = notification.category
            val timestamp = if (sbn.postTime > 0) sbn.postTime else now

            val data = NotificationData(
                id = "notif_${idCounter.incrementAndGet()}",
                packageName = packageName,
                title = title,
                content = text,
                timestamp = timestamp,
                category = category,
                isOngoing = isOngoing
            )

            val initialSize = queueSize()
            addNotification(data, now)
            if (queueSize() > initialSize) {
                val pkgHash = hashString(packageName)
                Log.d(TAG, "Captured notification from pkgHash: $pkgHash (queue size: ${queueSize()})")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error capturing/adding notification", e)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        addSbnToQueue(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val packageName = sbn.packageName ?: "unknown"
        val pkgHash = hashString(packageName)
        Log.d(TAG, "Removed notification from pkgHash: $pkgHash")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "NotificationCollectorService connected")
        try {
            val activeNotifs = activeNotifications
            if (activeNotifs != null) {
                Log.d(TAG, "Syncing ${activeNotifs.size} existing notifications from panel")
                for (sbn in activeNotifs) {
                    addSbnToQueue(sbn)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error fetching active notifications on connect", e)
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.w(TAG, "NotificationCollectorService disconnected")
    }
}
