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
 * Manages secure key generation and persistence using AndroidKeyStore.
 *
 * Generates an AES-256 master key in AndroidKeyStore (with StrongBox fallback)
 * and uses it to protect a 256-bit passphrase stored in SharedPreferences.
 */
class SecurityKeyManager @JvmOverloads constructor(
    private val context: Context? = null,
    private val customPrefs: SharedPreferences? = null
) {

    companion object {
        private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        private const val MASTER_KEY_ALIAS = "scope_db_master_key_v1"
        private const val PREFS_NAME = "scope_keystore_prefs"
        private const val ENCRYPTED_PASSPHRASE_KEY = "encrypted_db_passphrase"
        private const val IV_KEY = "db_passphrase_iv"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_LENGTH = 128
        private const val IV_SIZE = 12

        @Volatile
        private var fallbackMasterKey: SecretKey? = null
    }

    private val prefs: SharedPreferences? by lazy {
        customPrefs ?: context?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    /**
     * Retrieves the existing 256-bit database key or generates a new one safely.
     */
    @Synchronized
    fun getOrCreateDatabaseKey(): String {
        val existingEncrypted = prefs?.getString(ENCRYPTED_PASSPHRASE_KEY, null)
        val existingIv = prefs?.getString(IV_KEY, null)

        if (!existingEncrypted.isNullOrEmpty() && !existingIv.isNullOrEmpty()) {
            try {
                return decryptPassphrase(existingEncrypted, existingIv)
            } catch (e: Exception) {
                // If decryption fails, recreate key securely
            }
        }

        val newPassphrase = generate256BitHexKey()
        encryptAndSavePassphrase(newPassphrase)
        return newPassphrase
    }

    private fun generate256BitHexKey(): String {
        val randomBytes = ByteArray(32)
        SecureRandom().nextBytes(randomBytes)
        val sb = StringBuilder(64)
        for (b in randomBytes) {
            sb.append(String.format("%02x", b))
        }
        return sb.toString()
    }

    private fun getOrCreateMasterKey(): SecretKey {
        try {
            val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
            if (keyStore.containsAlias(MASTER_KEY_ALIAS)) {
                val entry = keyStore.getEntry(MASTER_KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
                if (entry != null) {
                    return entry.secretKey
                }
            }

            try {
                return generateMasterKey(useStrongBox = true)
            } catch (e: Exception) {
                return generateMasterKey(useStrongBox = false)
            }
        } catch (e: Exception) {
            // AndroidKeyStore unavailable (e.g. host JVM unit test environment)
            val existing = fallbackMasterKey
            if (existing != null) {
                return existing
            }
            val keyGen = KeyGenerator.getInstance("AES")
            keyGen.init(256)
            val newKey = keyGen.generateKey()
            fallbackMasterKey = newKey
            return newKey
        }
    }

    private fun generateMasterKey(useStrongBox: Boolean): SecretKey {
        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            KEYSTORE_PROVIDER
        )

        val builder = KeyGenParameterSpec.Builder(
            MASTER_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)

        if (useStrongBox) {
            try {
                builder.setIsStrongBoxBacked(true)
            } catch (e: NoSuchMethodError) {
                // Not supported on older API levels
            }
        }

        keyGenerator.init(builder.build())
        return keyGenerator.generateKey()
    }

    private fun encryptAndSavePassphrase(passphrase: String) {
        val masterKey = getOrCreateMasterKey()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, masterKey)
        val iv = cipher.iv
        val encryptedBytes = cipher.doFinal(passphrase.toByteArray(Charsets.UTF_8))

        val encryptedBase64 = encodeBase64(encryptedBytes)
        val ivBase64 = encodeBase64(iv)

        prefs?.edit()
            ?.putString(ENCRYPTED_PASSPHRASE_KEY, encryptedBase64)
            ?.putString(IV_KEY, ivBase64)
            ?.apply()
    }

    private fun decryptPassphrase(encryptedBase64: String, ivBase64: String): String {
        val masterKey = getOrCreateMasterKey()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        val encryptedBytes = decodeBase64(encryptedBase64)
        val ivBytes = decodeBase64(ivBase64)

        val gcmSpec = GCMParameterSpec(GCM_TAG_LENGTH, ivBytes)
        cipher.init(Cipher.DECRYPT_MODE, masterKey, gcmSpec)
        val decryptedBytes = cipher.doFinal(encryptedBytes)
        return String(decryptedBytes, Charsets.UTF_8)
    }

    private fun encodeBase64(bytes: ByteArray): String {
        return try {
            Base64.encodeToString(bytes, Base64.NO_WRAP)
        } catch (e: Exception) {
            java.util.Base64.getEncoder().encodeToString(bytes)
        }
    }

    private fun decodeBase64(str: String): ByteArray {
        return try {
            Base64.decode(str, Base64.NO_WRAP)
        } catch (e: Exception) {
            java.util.Base64.getDecoder().decode(str)
        }
    }
}
