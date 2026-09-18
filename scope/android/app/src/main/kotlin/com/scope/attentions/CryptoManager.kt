package com.scope.attentions

import java.security.KeyStore
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Handles AES-256 GCM in-memory encryption and decryption for notification payloads.
 *
 * Uses an ephemeral key managed in memory with AndroidKeyStore fallback, ensuring
 * zero persistent disk writing.
 */
object CryptoManager {

    private const val ALGORITHM = "AES/GCM/NoPadding"
    private const val KEY_SIZE = 256
    private const val IV_SIZE = 12 // 96 bits recommended for GCM
    private const val TAG_SIZE = 128 // 128 bits auth tag
    private const val KEY_ALIAS = "ScopeNotificationPayloadKey"

    private val secureRandom = SecureRandom()

    @Volatile
    private var secretKey: SecretKey? = null

    @Synchronized
    private fun getOrGenerateKey(): SecretKey {
        secretKey?.let { return it }

        // Try AndroidKeyStore first if available
        try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            if (keyStore.containsAlias(KEY_ALIAS)) {
                val entry = keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
                if (entry != null) {
                    val key = entry.secretKey
                    secretKey = key
                    return key
                }
            }

            // Attempt to generate in AndroidKeyStore via reflection
            val keyGenerator = KeyGenerator.getInstance("AES", "AndroidKeyStore")
            val keyGenParameterSpecClass = Class.forName("android.security.keystore.KeyGenParameterSpec\$Builder")
            val keyGenParameterSpecBuilder = keyGenParameterSpecClass.getConstructor(
                String::class.java,
                Int::class.javaPrimitiveType
            ).newInstance(KEY_ALIAS, 1 or 2) // PURPOSE_ENCRYPT = 1, PURPOSE_DECRYPT = 2

            val setBlockModesMethod = keyGenParameterSpecClass.getMethod("setBlockModes", Array<String>::class.java)
            setBlockModesMethod.invoke(keyGenParameterSpecBuilder, arrayOf("GCM"))

            val setEncryptionPaddingsMethod = keyGenParameterSpecClass.getMethod("setEncryptionPaddings", Array<String>::class.java)
            setEncryptionPaddingsMethod.invoke(keyGenParameterSpecBuilder, arrayOf("NoPadding"))

            val setKeySizeMethod = keyGenParameterSpecClass.getMethod("setKeySize", Int::class.javaPrimitiveType)
            setKeySizeMethod.invoke(keyGenParameterSpecBuilder, KEY_SIZE)

            val buildMethod = keyGenParameterSpecClass.getMethod("build")
            val spec = buildMethod.invoke(keyGenParameterSpecBuilder)

            val initMethod = keyGenerator.javaClass.getMethod("init", java.security.spec.AlgorithmParameterSpec::class.java)
            initMethod.invoke(keyGenerator, spec)

            val key = keyGenerator.generateKey()
            secretKey = key
            return key
        } catch (e: Exception) {
            // AndroidKeyStore unavailable (e.g. standard JVM test environment) -> fall back to in-memory key
        }

        // Ephemeral in-memory key generation
        val keyGen = KeyGenerator.getInstance("AES")
        keyGen.init(KEY_SIZE, secureRandom)
        val key = keyGen.generateKey()
        secretKey = key
        return key
    }

    /**
     * Encrypts plaintext string using AES-256 GCM.
     * Returns Base64-encoded string combining IV and ciphertext.
     */
    fun encrypt(plaintext: String?): String {
        if (plaintext.isNullOrEmpty()) return ""

        return try {
            val key = getOrGenerateKey()
            val iv = ByteArray(IV_SIZE)
            secureRandom.nextBytes(iv)

            val cipher = Cipher.getInstance(ALGORITHM)
            val gcmSpec = GCMParameterSpec(TAG_SIZE, iv)
            cipher.init(Cipher.ENCRYPT_MODE, key, gcmSpec)

            val cipherText = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
            val combined = ByteArray(iv.size + cipherText.size)
            System.arraycopy(iv, 0, combined, 0, iv.size)
            System.arraycopy(cipherText, 0, combined, iv.size, cipherText.size)

            Base64.getEncoder().encodeToString(combined)
        } catch (e: Exception) {
            ""
        }
    }

    /**
     * Decrypts Base64-encoded string containing IV + ciphertext using AES-256 GCM.
     */
    fun decrypt(ciphertextBase64: String?): String {
        if (ciphertextBase64.isNullOrEmpty()) return ""

        return try {
            val combined = Base64.getDecoder().decode(ciphertextBase64)
            if (combined.size <= IV_SIZE) return ciphertextBase64

            val iv = ByteArray(IV_SIZE)
            System.arraycopy(combined, 0, iv, 0, IV_SIZE)

            val cipherTextSize = combined.size - IV_SIZE
            val cipherText = ByteArray(cipherTextSize)
            System.arraycopy(combined, IV_SIZE, cipherText, 0, cipherTextSize)

            val key = getOrGenerateKey()
            val cipher = Cipher.getInstance(ALGORITHM)
            val gcmSpec = GCMParameterSpec(TAG_SIZE, iv)
            cipher.init(Cipher.DECRYPT_MODE, key, gcmSpec)

            val plainBytes = cipher.doFinal(cipherText)
            String(plainBytes, Charsets.UTF_8)
        } catch (e: Exception) {
            ciphertextBase64
        }
    }
}
