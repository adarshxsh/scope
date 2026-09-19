package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.security.SecureRandom
import java.util.Arrays
import java.util.Base64
import java.util.concurrent.ConcurrentLinkedQueue
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notification payloads (title, content) are encrypted in memory using an
 * ephemeral AES-256-GCM key before being placed in a static [queue].
 * The queue is drained and decrypted by [MainActivity] when Flutter requests them via MethodChannel.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Thread-safe queue of captured notifications. */
        private val queue = ConcurrentLinkedQueue<NotificationData>()

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /** Ephemeral AES-256 key byte array stored in volatile memory. */
        private var keyBytes: ByteArray? = null

        /** Ephemeral SecretKey reference. */
        private var secretKey: SecretKey? = null

        /**
         * Returns or generates the active ephemeral AES-256 key.
         */
        @Synchronized
        fun getOrCreateKey(): SecretKey {
            val existingKey = secretKey
            if (existingKey != null) {
                return existingKey
            }
            val kgen = KeyGenerator.getInstance("AES")
            kgen.init(256, SecureRandom())
            val key = kgen.generateKey()
            val bytes = key.encoded
            keyBytes = bytes
            val sKey = SecretKeySpec(bytes, "AES")
            secretKey = sKey
            return sKey
        }

        /**
         * Securely erases key bytes in memory and clears references.
         */
        @Synchronized
        fun clearKey() {
            val bytes = keyBytes
            if (bytes != null) {
                Arrays.fill(bytes, 0.toByte())
                keyBytes = null
            }
            secretKey = null
        }

        /**
         * Encrypts plaintext string using AES-256-GCM.
         * Returns Base64 string of combined (IV 12-bytes + Ciphertext).
         */
        fun encryptPayload(plaintext: String): String {
            if (plaintext.isEmpty()) return ""
            return try {
                val key = getOrCreateKey()
                val iv = ByteArray(12)
                SecureRandom().nextBytes(iv)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                val spec = GCMParameterSpec(128, iv)
                cipher.init(Cipher.ENCRYPT_MODE, key, spec)
                val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
                val combined = ByteArray(iv.size + ciphertext.size)
                System.arraycopy(iv, 0, combined, 0, iv.size)
                System.arraycopy(ciphertext, 0, combined, iv.size, ciphertext.size)
                Base64.getEncoder().encodeToString(combined)
            } catch (e: Exception) {
                tryLogE("Encryption failed", e)
                ""
            }
        }

        /**
         * Decrypts Base64 string of combined (IV 12-bytes + Ciphertext) using AES-256-GCM.
         * Returns restored plaintext string.
         */
        fun decryptPayload(encryptedBase64: String): String {
            if (encryptedBase64.isEmpty()) return ""
            return try {
                val key = secretKey ?: getOrCreateKey()
                val combined = Base64.getDecoder().decode(encryptedBase64)
                if (combined.size <= 12) return ""
                val iv = combined.copyOfRange(0, 12)
                val ciphertext = combined.copyOfRange(12, combined.size)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                val spec = GCMParameterSpec(128, iv)
                cipher.init(Cipher.DECRYPT_MODE, key, spec)
                val plaintextBytes = cipher.doFinal(ciphertext)
                String(plaintextBytes, Charsets.UTF_8)
            } catch (e: Exception) {
                tryLogE("Decryption failed", e)
                ""
            }
        }

        /**
         * Drains all notifications from the queue, decrypts payload fields, and returns them.
         * Called by [MainActivity] when Flutter requests notifications.
         * After this call, the queue is empty.
         */
        fun drainQueue(): List<NotificationData> {
            val result = mutableListOf<NotificationData>()
            while (true) {
                val item = queue.poll() ?: break
                val decryptedTitle = decryptPayload(item.title)
                val decryptedContent = decryptPayload(item.content)
                val restoredData = item.copy(
                    title = decryptedTitle,
                    content = decryptedContent
                )
                result.add(restoredData)
            }
            return result
        }

        /**
         * Returns the current queue size (for diagnostics).
         */
        fun queueSize(): Int = queue.size

        /**
         * Clears all items in the queue (for tests or reset).
         */
        fun clearQueue() {
            queue.clear()
        }

        /**
         * Gets a direct view of raw queue items (for unit tests to verify in-memory encryption).
         */
        fun getRawQueueItems(): List<NotificationData> {
            return queue.toList()
        }

        /**
         * Directly adds a pre-encrypted item to queue (for testing).
         */
        fun enqueueRaw(data: NotificationData) {
            queue.add(data)
        }

        /**
         * Safely logs errors without crashing in unmocked Android Log environments.
         */
        private fun tryLogE(msg: String, e: Throwable) {
            try {
                Log.e(TAG, msg, e)
            } catch (_: Throwable) {
                // Ignore log error in headless unit tests
            }
        }

        private fun tryLogD(msg: String) {
            try {
                Log.d(TAG, msg)
            } catch (_: Throwable) {
                // Ignore log error in headless unit tests
            }
        }
    }

    private fun addSbnToQueue(sbn: StatusBarNotification) {
        try {
            val extras = sbn.notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: "unknown"

            // Ignore if same package, title, and content already exist in queue
            val isDuplicate = queue.any {
                it.packageName == packageName &&
                decryptPayload(it.title) == title &&
                decryptPayload(it.content) == text
            }
            if (isDuplicate) {
                return
            }

            val encryptedTitle = encryptPayload(title)
            val encryptedContent = encryptPayload(text)

            val data = NotificationData(
                id = "notif_${++idCounter}",
                packageName = packageName,
                title = encryptedTitle,
                content = encryptedContent,
                timestamp = sbn.postTime,
                category = sbn.notification.category,
                isOngoing = isOngoing
            )

            queue.add(data)
            tryLogD("Captured: ${data.packageName} - ${NotificationRedactor.redactTitle(title)}")
        } catch (e: Exception) {
            tryLogE("Error capturing/adding notification", e)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        addSbnToQueue(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val removedTitle = sbn.notification.extras?.getCharSequence("android.title")?.toString()
        tryLogD("Removed: ${sbn.packageName} - ${NotificationRedactor.redactTitle(removedTitle)}")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        getOrCreateKey()
        tryLogD("NotificationCollectorService connected")
        try {
            val activeNotifs = activeNotifications
            if (activeNotifs != null) {
                tryLogD("Syncing ${activeNotifs.size} existing notifications from panel")
                for (sbn in activeNotifs) {
                    addSbnToQueue(sbn)
                }
            }
        } catch (e: Exception) {
            tryLogE("Error fetching active notifications on connect", e)
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        clearKey()
        clearQueue()
        tryLogD("NotificationCollectorService disconnected")
    }

    override fun onDestroy() {
        super.onDestroy()
        clearKey()
        clearQueue()
        tryLogD("NotificationCollectorService destroyed")
    }
}
