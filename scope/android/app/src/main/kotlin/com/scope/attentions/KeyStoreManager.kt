package com.scope.attentions

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * KeyStoreManager manages hardware-backed key generation and secure database passphrase
 * storage using AndroidKeyStore with TEE fallback support.
 */
class KeyStoreManager(
    private val keyAlias: String = DEFAULT_KEY_ALIAS,
    private val prefsName: String = DEFAULT_PREFS_NAME
) {

    companion object {
        const val DEFAULT_KEY_ALIAS = "scope_db_encryption_key"
        const val DEFAULT_PREFS_NAME = "scope_keystore_prefs"
        private const val KEY_PASSPHRASE_ENC = "encrypted_passphrase"
        private const val KEY_PASSPHRASE_IV = "passphrase_iv"
        private const val KEY_IS_TEE_FALLBACK = "is_tee_fallback"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val AES_GCM_NO_PADDING = "AES/GCM/NoPadding"
        private const val GCM_TAG_LENGTH = 128
        private const val PASSPHRASE_SIZE_BYTES = 32 // 256-bit passphrase
    }

    private var isStrongBoxUsed = false
    private var isTeeFallbackUsed = false

    fun isStrongBoxUsed(): Boolean = isStrongBoxUsed
    fun isTeeFallbackUsed(): Boolean = isTeeFallbackUsed

    /**
     * Retrieves or generates a 256-bit AES database passphrase securely.
     */
    @Synchronized
    fun getOrCreateDatabasePassphrase(context: Context): String {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val storedEncPassphrase = prefs.getString(KEY_PASSPHRASE_ENC, null)
        val storedIv = prefs.getString(KEY_PASSPHRASE_IV, null)

        if (storedEncPassphrase != null && storedIv != null) {
            try {
                val decrypted = decryptPassphrase(storedEncPassphrase, storedIv)
                if (decrypted != null) {
                    return decrypted
                }
            } catch (e: Exception) {
                // If decryption fails, clear stored values and regenerate below
            }
        }

        // Generate a new 256-bit passphrase
        val secretKey = getOrCreateSecretKey()
        val rawPassphrase = ByteArray(PASSPHRASE_SIZE_BYTES)
        SecureRandom().nextBytes(rawPassphrase)
        val passphraseHex = bytesToHex(rawPassphrase)

        if (secretKey != null) {
            try {
                val cipher = Cipher.getInstance(AES_GCM_NO_PADDING)
                cipher.init(Cipher.ENCRYPT_MODE, secretKey)
                val iv = cipher.iv
                val encryptedBytes = cipher.doFinal(passphraseHex.toByteArray(Charsets.UTF_8))

                val encBase64 = Base64.encodeToString(encryptedBytes, Base64.NO_WRAP)
                val ivBase64 = Base64.encodeToString(iv, Base64.NO_WRAP)

                prefs.edit()
                    .putString(KEY_PASSPHRASE_ENC, encBase64)
                    .putString(KEY_PASSPHRASE_IV, ivBase64)
                    .putBoolean(KEY_IS_TEE_FALLBACK, isTeeFallbackUsed)
                    .apply()
            } catch (e: Exception) {
                // Fallback store in preferences in software mode if Cipher fails
                val encBase64 = Base64.encodeToString(passphraseHex.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
                prefs.edit().putString(KEY_PASSPHRASE_ENC, encBase64).putString(KEY_PASSPHRASE_IV, "PLAIN").apply()
            }
        } else {
            // Software fallback for environments without AndroidKeyStore (e.g. JVM tests)
            val encBase64 = Base64.encodeToString(passphraseHex.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
            prefs.edit().putString(KEY_PASSPHRASE_ENC, encBase64).putString(KEY_PASSPHRASE_IV, "PLAIN").apply()
        }

        return passphraseHex
    }

    private fun decryptPassphrase(encBase64: String, ivBase64: String): String? {
        if (ivBase64 == "PLAIN") {
            val bytes = Base64.decode(encBase64, Base64.NO_WRAP)
            return String(bytes, Charsets.UTF_8)
        }

        val secretKey = getOrCreateSecretKey() ?: return null
        val encryptedBytes = Base64.decode(encBase64, Base64.NO_WRAP)
        val iv = Base64.decode(ivBase64, Base64.NO_WRAP)

        val cipher = Cipher.getInstance(AES_GCM_NO_PADDING)
        val spec = GCMParameterSpec(GCM_TAG_LENGTH, iv)
        cipher.init(Cipher.DECRYPT_MODE, secretKey, spec)

        val decryptedBytes = cipher.doFinal(encryptedBytes)
        return String(decryptedBytes, Charsets.UTF_8)
    }

    fun getOrCreateSecretKey(): SecretKey? {
        return try {
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
            keyStore.load(null)

            if (keyStore.containsAlias(keyAlias)) {
                val entry = keyStore.getEntry(keyAlias, null) as? KeyStore.SecretKeyEntry
                return entry?.secretKey
            }

            generateKeyStoreKey()
        } catch (e: Exception) {
            // AndroidKeyStore provider not available (e.g. JVM unit test runner)
            null
        }
    }

    fun generateKeyStoreKey(): SecretKey? {
        return try {
            generateKeyWithStrongBoxFallback()
        } catch (e: Exception) {
            null
        }
    }

    private fun generateKeyWithStrongBoxFallback(): SecretKey? {
        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE
        )

        // Attempt 1: Try StrongBox backing if Android P or above
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                val strongBoxSpec = KeyGenParameterSpec.Builder(
                    keyAlias,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .setIsStrongBoxBacked(true)
                    .build()

                keyGenerator.init(strongBoxSpec)
                val key = keyGenerator.generateKey()
                isStrongBoxUsed = true
                isTeeFallbackUsed = false
                return key
            } catch (e: Exception) {
                // StrongBox unavailable or failed, fallback to TEE
                isStrongBoxUsed = false
                isTeeFallbackUsed = true
            }
        } else {
            isTeeFallbackUsed = true
        }

        // Attempt 2: Fallback to TEE (software/TEE KeyStore)
        val teeSpec = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()

        keyGenerator.init(teeSpec)
        val key = keyGenerator.generateKey()
        isTeeFallbackUsed = true
        return key
    }

    private fun bytesToHex(bytes: ByteArray): String {
        val sb = StringBuilder()
        for (b in bytes) {
            sb.append(String.format("%02x", b))
        }
        return sb.toString()
    }
}
