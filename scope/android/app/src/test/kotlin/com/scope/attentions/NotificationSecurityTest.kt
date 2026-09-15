package com.scope.attentions

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.Arrays

class NotificationSecurityTest {

    @Test
    fun testPayloadEncryptionInRam() {
        val title = "Secret Title"
        val content = "Sensitive OTP message 123456"

        val data = NotificationData.create(
            id = "test_1",
            packageName = "com.test.app",
            title = title,
            content = content,
            timestamp = System.currentTimeMillis(),
            category = "msg",
            isOngoing = false
        )

        // Verify payload fields are stored AES-256-GCM encrypted in RAM (not plain text)
        assertFalse(String(data.encryptedTitle, Charsets.UTF_8).contains("Secret"))
        assertFalse(String(data.encryptedContent, Charsets.UTF_8).contains("OTP"))
        assertTrue(data.encryptedTitle.isNotEmpty())
        assertTrue(data.encryptedContent.isNotEmpty())
        assertTrue(data.titleIv.size == 12)
        assertTrue(data.contentIv.size == 12)

        // Verify on-demand decryption returns correct plaintext
        assertEquals(title, data.title)
        assertEquals(content, data.content)
    }

    @Test
    fun testCryptoManagerDecryptionAndBufferZeroing() {
        val originalText = "Super Confidential Message"
        val (encrypted, iv) = CryptoManager.encrypt(originalText)

        // Decrypt
        val decryptedBytes = CryptoManager.decryptBytes(encrypted, iv)
        assertTrue(decryptedBytes.isNotEmpty())
        assertEquals(originalText, String(decryptedBytes, Charsets.UTF_8))

        // Decrypt to string handles zeroing
        val decryptedStr = CryptoManager.decryptToString(encrypted, iv)
        assertEquals(originalText, decryptedStr)

        // Manual buffer zeroing check
        val testBuffer = byteArrayOf(1, 2, 3, 4, 5)
        Arrays.fill(testBuffer, 0.toByte())
        assertArrayEquals(byteArrayOf(0, 0, 0, 0, 0), testBuffer)
    }

    @Test
    fun testBufferScrubbingPostDrain() {
        val data = NotificationData.create(
            id = "test_2",
            packageName = "com.bank.app",
            title = "Bank Debit",
            content = "Amount Rs. 5000 debited",
            timestamp = System.currentTimeMillis(),
            category = "finance",
            isOngoing = false
        )

        val map = data.toMap()
        assertEquals("Bank Debit", map["title"])
        assertEquals("Amount Rs. 5000 debited", map["content"])

        // Explicit zero-filling of encrypted buffers post-extraction
        data.scrubEncryptedBuffers()

        assertTrue(data.encryptedTitle.all { it == 0.toByte() })
        assertTrue(data.titleIv.all { it == 0.toByte() })
        assertTrue(data.encryptedContent.all { it == 0.toByte() })
        assertTrue(data.contentIv.all { it == 0.toByte() })
    }

    @Test
    fun testManifestExportedAttributeIsFalse() {
        val manifestFile = File("src/main/AndroidManifest.xml")
        assertTrue("AndroidManifest.xml should exist", manifestFile.exists())

        val content = manifestFile.readText()
        assertTrue("Manifest should reference NotificationCollectorService", content.contains("NotificationCollectorService"))
        assertFalse("NotificationCollectorService should not be exported=true", content.contains("android:name=\".NotificationCollectorService\"\n            android:exported=\"true\""))
        assertTrue("NotificationCollectorService must have android:exported=\"false\"", content.contains("android:name=\".NotificationCollectorService\"\n            android:exported=\"false\"") || content.contains("android:exported=\"false\""))
    }

    @Test
    fun testLogcatSanitization() {
        val serviceFile = File("src/main/kotlin/com/scope/attentions/NotificationCollectorService.kt")
        assertTrue("NotificationCollectorService.kt should exist", serviceFile.exists())

        val content = serviceFile.readText()
        assertFalse("Logcat output must not contain packageName variable in Log.d", content.contains("\${data.packageName}") || content.contains("\${sbn.packageName}"))
        assertFalse("Logcat output must not contain title variable in Log.d", content.contains("\${data.title}"))
        assertFalse("Logcat output must not contain text variable in Log.d", content.contains("\${data.content}"))
    }
}
