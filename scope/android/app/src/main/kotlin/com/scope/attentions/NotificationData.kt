package com.scope.attentions

import java.util.Arrays

/**
 * Data class representing a captured Android notification.
 *
 * This mirrors the Dart [AppNotification] model. Data flows:
 *   Android NotificationListenerService → NotificationData → MethodChannel → Dart AppNotification
 *
 * Sensitive notification payload fields (title, content) are stored AES-256-GCM encrypted
 * while queued in RAM.
 */
class NotificationData(
    val id: String,
    val packageName: String,
    val encryptedTitle: ByteArray,
    val titleIv: ByteArray,
    val encryptedContent: ByteArray,
    val contentIv: ByteArray,
    val timestamp: Long,
    val category: String?,
    val isOngoing: Boolean
) {
    /**
     * Secondary constructor that accepts raw plaintext title and content,
     * encrypts them using AES-256-GCM, and zero-fills transient plaintext byte buffers.
     */
    constructor(
        id: String,
        packageName: String,
        title: String,
        content: String,
        timestamp: Long,
        category: String?,
        isOngoing: Boolean,
        titleEnc: Pair<ByteArray, ByteArray> = CryptoManager.encrypt(title),
        contentEnc: Pair<ByteArray, ByteArray> = CryptoManager.encrypt(content)
    ) : this(
        id = id,
        packageName = packageName,
        encryptedTitle = titleEnc.first,
        titleIv = titleEnc.second,
        encryptedContent = contentEnc.first,
        contentIv = contentEnc.second,
        timestamp = timestamp,
        category = category,
        isOngoing = isOngoing
    )

    /**
     * Decrypts title on demand and zero-fills transient decrypted byte buffer.
     */
    val title: String
        get() = CryptoManager.decryptToString(encryptedTitle, titleIv)

    /**
     * Decrypts content on demand and zero-fills transient decrypted byte buffer.
     */
    val content: String
        get() = CryptoManager.decryptToString(encryptedContent, contentIv)

    /**
     * Scrubs and zero-fills internal encrypted byte buffers post-extraction.
     */
    fun scrubEncryptedBuffers() {
        Arrays.fill(encryptedTitle, 0.toByte())
        Arrays.fill(titleIv, 0.toByte())
        Arrays.fill(encryptedContent, 0.toByte())
        Arrays.fill(contentIv, 0.toByte())
    }

    /**
     * Converts to a HashMap for MethodChannel serialization.
     * Keys match the Dart [AppNotification.fromMap] expectations.
     */
    fun toMap(): HashMap<String, Any?> {
        val decryptedTitle = title
        val decryptedContent = content
        return hashMapOf(
            "id" to id,
            "packageName" to packageName,
            "title" to decryptedTitle,
            "content" to decryptedContent,
            "timestamp" to timestamp,
            "category" to category,
            "isOngoing" to isOngoing
        )
    }

    companion object {
        fun create(
            id: String,
            packageName: String,
            title: String,
            content: String,
            timestamp: Long,
            category: String?,
            isOngoing: Boolean
        ): NotificationData {
            return NotificationData(
                id = id,
                packageName = packageName,
                title = title,
                content = content,
                timestamp = timestamp,
                category = category,
                isOngoing = isOngoing
            )
        }
    }
}
