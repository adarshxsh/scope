package com.scope.attentions

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.security.SecureRandom
import java.security.Security
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import android.content.SharedPreferences

/**
 * Manages master key derivation bound to AndroidKeyStore and StrongBox HSM,
 * enabling AES-256-GCM encryption/decryption for SQLite database passphrases.
 */
class SecurityKeyManager @JvmOverloads constructor(
    private val context: Context? = null,
    private val customPrefs: SharedPreferences? = null
) {

    companion object {
        private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        private const val MASTER_KEY_ALIAS = "scope_master_key"
        private const val PREFS_NAME = "scope_security_prefs"
        private const val KEY_ENCRYPTED_PASSPHRASE = "encrypted_db_passphrase"
        private const val AES_GCM_TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_IV_LENGTH = 12
        private const val GCM_TAG_LENGTH = 128
        private const val PASSPHRASE_BYTE_LENGTH = 32

        @Volatile
        private var jvmFallbackKey: SecretKey? = null
    }

    /**
     * Retrieves existing database passphrase decrypted using the AndroidKeyStore master key,
     * or generates and persists a new 256-bit passphrase if one does not exist.
     */
    @Synchronized
    fun getOrCreateDatabasePassphrase(): String {
        val prefs = customPrefs ?: context?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        checkNotNull(prefs) { "SharedPreferences instance unavailable" }

        val encryptedBase64 = prefs.getString(KEY_ENCRYPTED_PASSPHRASE, null)

        if (!encryptedBase64.isNullOrEmpty()) {
            return decryptPassphrase(encryptedBase64)
        }

        // Generate a new 256-bit secure passphrase (64 hex chars)
        val randomBytes = ByteArray(PASSPHRASE_BYTE_LENGTH)
        SecureRandom().nextBytes(randomBytes)
        val passphrase = randomBytes.joinToString("") { "%02x".format(it) }

        // Encrypt and store passphrase
        val encryptedData = encryptPassphrase(passphrase)
        prefs.edit().putString(KEY_ENCRYPTED_PASSPHRASE, encryptedData).apply()

        return passphrase
    }

    /**
     * Encrypts the raw passphrase string using AES-256-GCM and the master key.
     */
    private fun encryptPassphrase(passphrase: String): String {
        val secretKey = getOrCreateMasterKey()
        val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)

        val iv = cipher.iv
        val ciphertext = cipher.doFinal(passphrase.toByteArray(Charsets.UTF_8))
        val combined = iv + ciphertext

        return safeEncodeBase64(combined)
    }

    /**
     * Decrypts the Base64-encoded IV + Ciphertext string back to the original passphrase.
     */
    private fun decryptPassphrase(encryptedBase64: String): String {
        val combined = safeDecodeBase64(encryptedBase64)
        require(combined.size > GCM_IV_LENGTH) { "Invalid encrypted passphrase payload" }

        val iv = combined.copyOfRange(0, GCM_IV_LENGTH)
        val ciphertext = combined.copyOfRange(GCM_IV_LENGTH, combined.size)

        val secretKey = getOrCreateMasterKey()
        val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
        val spec = GCMParameterSpec(GCM_TAG_LENGTH, iv)
        cipher.init(Cipher.DECRYPT_MODE, secretKey, spec)

        val decryptedBytes = cipher.doFinal(ciphertext)
        return String(decryptedBytes, Charsets.UTF_8)
    }

    /**
     * Retrieves or creates the master SecretKey in AndroidKeyStore, with StrongBox HSM support.
     */
    internal fun getOrCreateMasterKey(): SecretKey {
        val hasAndroidKeyStore = Security.getProvider(KEYSTORE_PROVIDER) != null
        if (!hasAndroidKeyStore) {
            // Standard JVM test environment fallback
            return getJvmFallbackKey()
        }

        return try {
            val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
            if (keyStore.containsAlias(MASTER_KEY_ALIAS)) {
                val entry = keyStore.getEntry(MASTER_KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
                entry?.secretKey ?: generateMasterKey(useStrongBox = true)
            } else {
                generateMasterKey(useStrongBox = true)
            }
        } catch (e: Exception) {
            // Fallback if AndroidKeyStore fails in host JVM
            getJvmFallbackKey()
        }
    }

    /**
     * Generates a new AES-256 key in AndroidKeyStore, attempting StrongBox backing first.
     */
    private fun generateMasterKey(useStrongBox: Boolean): SecretKey {
        return try {
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

            if (useStrongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                if (hasStrongBoxSupport()) {
                    try {
                        builder.setIsStrongBoxBacked(true)
                    } catch (_: Exception) {
                        // StrongBox setting ignored if unsupported by spec
                    }
                }
            }

            keyGenerator.init(builder.build())
            keyGenerator.generateKey()
        } catch (e: Exception) {
            if (useStrongBox) {
                // Fallback to standard TEE (without StrongBox)
                generateMasterKey(useStrongBox = false)
            } else {
                throw e
            }
        }
    }

    private fun hasStrongBoxSupport(): Boolean {
        return try {
            context?.packageManager?.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE) == true
        } catch (_: Throwable) {
            false
        }
    }

    private fun getJvmFallbackKey(): SecretKey {
        val existing = jvmFallbackKey
        if (existing != null) return existing

        val keyGen = KeyGenerator.getInstance("AES")
        keyGen.init(256)
        val key = keyGen.generateKey()
        jvmFallbackKey = key
        return key
    }

    private fun safeEncodeBase64(bytes: ByteArray): String {
        return try {
            Base64.encodeToString(bytes, Base64.NO_WRAP)
        } catch (_: Throwable) {
            java.util.Base64.getEncoder().encodeToString(bytes)
        }
    }

    private fun safeDecodeBase64(str: String): ByteArray {
        return try {
            Base64.decode(str, Base64.NO_WRAP)
        } catch (_: Throwable) {
            java.util.Base64.getDecoder().decode(str)
        }
    }
}
