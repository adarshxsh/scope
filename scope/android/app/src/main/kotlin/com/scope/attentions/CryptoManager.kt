package com.scope.attentions

import java.security.SecureRandom
import java.util.Arrays
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Manages ephemeral AES-256-GCM encryption and memory scrubbing for transient notification payloads.
 *
 * Ephemeral key is generated per app session and resides only in RAM.
 */
object CryptoManager {
    private const val AES_KEY_SIZE = 256
    private const val GCM_IV_LENGTH = 12
    private const val GCM_TAG_LENGTH = 128
    private const val TRANSFORMATION = "AES/GCM/NoPadding"

    private val secureRandom = SecureRandom()

    private val secretKey: SecretKey by lazy {
        val keyGen = KeyGenerator.getInstance("AES")
        keyGen.init(AES_KEY_SIZE, secureRandom)
        keyGen.generateKey()
    }

    /**
     * Encrypts plaintext String using AES-256-GCM.
     * Immediately zero-fills the transient byte buffer created from string.
     * Returns Pair(ciphertext, iv).
     */
    fun encrypt(plainText: String): Pair<ByteArray, ByteArray> {
        val plainBytes = plainText.toByteArray(Charsets.UTF_8)
        try {
            return encryptBytes(plainBytes)
        } finally {
            Arrays.fill(plainBytes, 0.toByte())
        }
    }

    /**
     * Encrypts byte array using AES-256-GCM.
     * Returns Pair(ciphertext, iv).
     */
    fun encryptBytes(plainBytes: ByteArray): Pair<ByteArray, ByteArray> {
        val iv = ByteArray(GCM_IV_LENGTH)
        secureRandom.nextBytes(iv)

        val cipher = Cipher.getInstance(TRANSFORMATION)
        val spec = GCMParameterSpec(GCM_TAG_LENGTH, iv)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey, spec)

        val cipherText = cipher.doFinal(plainBytes)
        return Pair(cipherText, iv)
    }

    /**
     * Decrypts AES-256-GCM ciphertext byte array back to plaintext String.
     * Explicitly zero-fills the transient decrypted byte buffer before returning String.
     */
    fun decryptToString(cipherText: ByteArray, iv: ByteArray): String {
        if (cipherText.isEmpty()) return ""
        val decryptedBytes = decryptBytes(cipherText, iv)
        try {
            return String(decryptedBytes, Charsets.UTF_8)
        } finally {
            Arrays.fill(decryptedBytes, 0.toByte())
        }
    }

    /**
     * Decrypts AES-256-GCM ciphertext byte array to byte array.
     */
    fun decryptBytes(cipherText: ByteArray, iv: ByteArray): ByteArray {
        if (cipherText.isEmpty()) return ByteArray(0)
        return try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            val spec = GCMParameterSpec(GCM_TAG_LENGTH, iv)
            cipher.init(Cipher.DECRYPT_MODE, secretKey, spec)
            cipher.doFinal(cipherText)
        } catch (e: Exception) {
            ByteArray(0)
        }
    }
}
