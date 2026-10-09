package com.scope.attentions

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.security.KeyStore
import java.security.SecureRandom

/**
 * Native SecurityKeyManager managing database key derivation and storage via AndroidKeyStore
 * and EncryptedSharedPreferences.
 */
class SecurityKeyManager(private val context: Context) {

    companion object {
        private const val KEY_ALIAS = "com.scope.keystore.master_key"
        private const val PREFS_FILENAME = "com.scope.keystore.secure_prefs"
        private const val PASSPHRASE_KEY = "db_passphrase"
    }

    /**
     * Gets or creates the AES-256 master key in AndroidKeyStore.
     * Attempts StrongBox hardware backing first, falling back gracefully to standard
     * hardware-backed AndroidKeyStore if StrongBox is unavailable.
     */
    fun getOrCreateMasterKey(): MasterKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keyStore.containsAlias(KEY_ALIAS)) {
            return MasterKey.Builder(context, KEY_ALIAS).build()
        }

        return try {
            val spec = KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setIsStrongBoxBacked(true)
                .build()

            MasterKey.Builder(context, KEY_ALIAS)
                .setKeyGenParameterSpec(spec)
                .build()
        } catch (e: Exception) {
            val spec = KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setIsStrongBoxBacked(false)
                .build()

            MasterKey.Builder(context, KEY_ALIAS)
                .setKeyGenParameterSpec(spec)
                .build()
        }
    }

    /**
     * Retrieves or generates a cryptographically random 256-bit database passphrase
     * persisted inside EncryptedSharedPreferences.
     */
    fun getDatabasePassphrase(): String {
        val masterKey = getOrCreateMasterKey()
        val sharedPreferences = EncryptedSharedPreferences.create(
            context,
            PREFS_FILENAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )

        var passphrase = sharedPreferences.getString(PASSPHRASE_KEY, null)
        if (passphrase == null) {
            val randomBytes = ByteArray(32) // 256 bits
            SecureRandom().nextBytes(randomBytes)
            passphrase = randomBytes.joinToString("") { "%02x".format(it) }
            sharedPreferences.edit().putString(PASSPHRASE_KEY, passphrase).apply()
        }

        return passphrase
    }
}
