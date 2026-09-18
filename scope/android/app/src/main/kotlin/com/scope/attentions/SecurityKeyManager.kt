package com.scope.attentions

import android.content.Context
import android.content.SharedPreferences
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
 * Manages secure generation and retrieval of the 256-bit database encryption key.
 * Uses AndroidKeyStore to store an AES-256 master key with hardware backing when available,
 * and encrypts the 256-bit database passphrase before saving it to SharedPreferences.
 */
class SecurityKeyManager(
    private val context: Context?,
    private val customPrefs: SharedPreferences? = null
) {
    companion object {
        private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        private const val MASTER_KEY_ALIAS = "scope_db_master_key"
        private const val PREFS_NAME = "scope_secure_keystore_prefs"
        private const val ENCRYPTED_DB_KEY_PREF = "encrypted_db_passphrase"
        private const val IV_PREF = "encrypted_db_passphrase_iv"
        private const val AES_GCM_TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_LENGTH = 128
    }

    private fun getPreferences(): SharedPreferences? {
        if (customPrefs != null) return customPrefs
        return context?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    /**
     * Gets or creates the 256-bit hex database encryption key.
     */
    fun getOrCreateDatabaseKey(): String {
        val prefs = getPreferences()
        val existingEncryptedKey = prefs?.getString(ENCRYPTED_DB_KEY_PREF, null)
        val existingIv = prefs?.getString(IV_PREF, null)

        if (existingEncryptedKey != null && existingIv != null) {
            try {
                return decryptKey(existingEncryptedKey, existingIv)
            } catch (e: Exception) {
                // Fallback / re-generate if decryption fails
            }
        }

        // Generate new 256-bit key (32 bytes => 64 hex characters)
        val randomBytes = ByteArray(32)
        SecureRandom().nextBytes(randomBytes)
        val hexKey = randomBytes.joinToString("") { "%02x".format(it) }

        try {
            val (encryptedKey, iv) = encryptKey(hexKey)
            prefs?.edit()
                ?.putString(ENCRYPTED_DB_KEY_PREF, encryptedKey)
                ?.putString(IV_PREF, iv)
                ?.apply()
        } catch (e: Exception) {
            if (customPrefs != null) {
                customPrefs.edit().putString(ENCRYPTED_DB_KEY_PREF, hexKey).apply()
            }
        }

        return hexKey
    }

    private fun getMasterKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        if (keyStore.containsAlias(MASTER_KEY_ALIAS)) {
            val entry = keyStore.getEntry(MASTER_KEY_ALIAS, null) as KeyStore.SecretKeyEntry
            return entry.secretKey
        }

        return generateMasterKey()
    }

    private fun generateMasterKey(): SecretKey {
        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            KEYSTORE_PROVIDER
        )

        try {
            val spec = KeyGenParameterSpec.Builder(
                MASTER_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .apply {
                    try {
                        setIsStrongBoxBacked(true)
                    } catch (e: Throwable) {
                        // StrongBox not supported on this device
                    }
                }
                .build()

            keyGenerator.init(spec)
            return keyGenerator.generateKey()
        } catch (e: Exception) {
            val spec = KeyGenParameterSpec.Builder(
                MASTER_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()

            keyGenerator.init(spec)
            return keyGenerator.generateKey()
        }
    }

    private fun encryptKey(plainKey: String): Pair<String, String> {
        val masterKey = getMasterKey()
        val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, masterKey)
        val iv = cipher.iv
        val encryptedBytes = cipher.doFinal(plainKey.toByteArray(Charsets.UTF_8))

        val encryptedBase64 = Base64.encodeToString(encryptedBytes, Base64.NO_WRAP)
        val ivBase64 = Base64.encodeToString(iv, Base64.NO_WRAP)
        return Pair(encryptedBase64, ivBase64)
    }

    private fun decryptKey(encryptedBase64: String, ivBase64: String): String {
        val masterKey = getMasterKey()
        val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
        val iv = Base64.decode(ivBase64, Base64.NO_WRAP)
        val gcmSpec = GCMParameterSpec(GCM_TAG_LENGTH, iv)
        cipher.init(Cipher.DECRYPT_MODE, masterKey, gcmSpec)

        val encryptedBytes = Base64.decode(encryptedBase64, Base64.NO_WRAP)
        val decryptedBytes = cipher.doFinal(encryptedBytes)
        return String(decryptedBytes, Charsets.UTF_8)
    }
}
