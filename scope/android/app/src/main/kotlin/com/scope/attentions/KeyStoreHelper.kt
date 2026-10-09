package com.scope.attentions

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import java.security.KeyStore
import java.security.ProviderException
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

/**
 * Helper class for managing AndroidKeyStore hardware-bound AES-256 master keys
 * and secure database passphrase wrapping/unwrapping with StrongBox HSM support.
 */
class KeyStoreHelper(private val context: Context) {

    companion object {
        const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        const val MASTER_KEY_ALIAS = "scope_master_key"
        private const val PREFS_NAME = "scope_secure_prefs"
        private const val PREF_ENCRYPTED_PASSPHRASE = "encrypted_db_passphrase"
        private const val PREF_IV = "db_passphrase_iv"
        private const val PREF_IS_STRONGBOX = "is_strongbox_backed"
        private const val GCM_TAG_LENGTH = 128
        private const val PASSPHRASE_BYTE_SIZE = 32
    }

    private val keyStore: KeyStore by lazy {
        KeyStore.getInstance(KEYSTORE_PROVIDER).apply {
            load(null)
        }
    }

    /**
     * Retrieves or creates the hardware-backed AES-256 master key.
     */
    @Synchronized
    fun getOrCreateMasterKey(): SecretKey {
        if (keyStore.containsAlias(MASTER_KEY_ALIAS)) {
            val entry = keyStore.getEntry(MASTER_KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
            if (entry != null) {
                return entry.secretKey
            }
        }
        return generateMasterKey()
    }

    /**
     * Generates an AES-256 master key in AndroidKeyStore using GCM mode.
     * Attempts StrongBox HSM allocation first; falls back to standard hardware keystore
     * if StrongBox is unavailable.
     */
    @Synchronized
    fun generateMasterKey(): SecretKey {
        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            KEYSTORE_PROVIDER
        )

        val hasStrongBoxFeature = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)

        if (hasStrongBoxFeature) {
            try {
                val spec = createKeyGenParameterSpec(isStrongBox = true)
                keyGenerator.init(spec)
                val key = keyGenerator.generateKey()
                setStrongBoxFlag(true)
                return key
            } catch (e: Exception) {
                // If StrongBox is unsupported or unavailable at runtime, fallback gracefully
                if (e is StrongBoxUnavailableException ||
                    e is ProviderException ||
                    e.cause is StrongBoxUnavailableException
                ) {
                    // Fallback to standard hardware keystore below
                } else {
                    // Try fallback before failing
                }
            }
        }

        val spec = createKeyGenParameterSpec(isStrongBox = false)
        keyGenerator.init(spec)
        val key = keyGenerator.generateKey()
        setStrongBoxFlag(false)
        return key
    }

    private fun createKeyGenParameterSpec(isStrongBox: Boolean): KeyGenParameterSpec {
        val builder = KeyGenParameterSpec.Builder(
            MASTER_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)

        if (isStrongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(true)
        }

        return builder.build()
    }

    /**
     * Securely unwraps or generates the database encryption passphrase.
     */
    @Synchronized
    fun getDatabasePassphrase(): String {
        val masterKey = getOrCreateMasterKey()
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        val encryptedPassphraseB64 = prefs.getString(PREF_ENCRYPTED_PASSPHRASE, null)
        val ivB64 = prefs.getString(PREF_IV, null)

        if (encryptedPassphraseB64 != null && ivB64 != null) {
            try {
                return unwrapPassphrase(masterKey, encryptedPassphraseB64, ivB64)
            } catch (e: Exception) {
                // In case of corruption or key invalidation, clear and regenerate
                prefs.edit().remove(PREF_ENCRYPTED_PASSPHRASE).remove(PREF_IV).apply()
            }
        }

        // Generate a new cryptographically secure passphrase (64-char hex string)
        val rawPassphraseBytes = ByteArray(PASSPHRASE_BYTE_SIZE)
        SecureRandom().nextBytes(rawPassphraseBytes)
        val passphraseString = bytesToHex(rawPassphraseBytes)

        // Encrypt passphrase using master key + random GCM IV
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, masterKey)
        val iv = cipher.iv
        val encryptedBytes = cipher.doFinal(passphraseString.toByteArray(Charsets.UTF_8))

        val encryptedB64 = Base64.encodeToString(encryptedBytes, Base64.NO_WRAP)
        val newIvB64 = Base64.encodeToString(iv, Base64.NO_WRAP)

        prefs.edit()
            .putString(PREF_ENCRYPTED_PASSPHRASE, encryptedB64)
            .putString(PREF_IV, newIvB64)
            .apply()

        return passphraseString
    }

    private fun unwrapPassphrase(masterKey: SecretKey, encryptedB64: String, ivB64: String): String {
        val encryptedBytes = Base64.decode(encryptedB64, Base64.NO_WRAP)
        val iv = Base64.decode(ivB64, Base64.NO_WRAP)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val spec = GCMParameterSpec(GCM_TAG_LENGTH, iv)
        cipher.init(Cipher.DECRYPT_MODE, masterKey, spec)

        val decryptedBytes = cipher.doFinal(encryptedBytes)
        return String(decryptedBytes, Charsets.UTF_8)
    }

    /**
     * Returns whether StrongBox HSM is currently backed and active for this keystore helper.
     */
    fun isStrongBoxSupported(): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.contains(PREF_IS_STRONGBOX)) {
            return prefs.getBoolean(PREF_IS_STRONGBOX, false)
        }
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
    }

    /**
     * Checks if the master key resides inside secure hardware.
     */
    fun isHardwareBacked(): Boolean {
        return try {
            val masterKey = getOrCreateMasterKey()
            val factory = SecretKeyFactory.getInstance(masterKey.algorithm, KEYSTORE_PROVIDER)
            val keyInfo = factory.getKeySpec(masterKey, KeyInfo::class.java) as KeyInfo
            keyInfo.isInsideSecureHardware
        } catch (e: Exception) {
            false
        }
    }

    private fun setStrongBoxFlag(isStrongBox: Boolean) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putBoolean(PREF_IS_STRONGBOX, isStrongBox).apply()
    }

    private fun bytesToHex(bytes: ByteArray): String {
        val sb = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            sb.append(String.format("%02x", b))
        }
        return sb.toString()
    }
}
