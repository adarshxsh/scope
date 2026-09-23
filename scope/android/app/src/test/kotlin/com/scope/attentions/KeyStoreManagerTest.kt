package com.scope.attentions

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class KeyStoreManagerTest {

    private lateinit var keyStoreManager: KeyStoreManager

    @Before
    fun setUp() {
        keyStoreManager = KeyStoreManager(
            keyAlias = "test_scope_key",
            prefsName = "test_prefs"
        )
    }

    @Test
    fun testKeyStoreManagerInitialization() {
        assertNotNull(keyStoreManager)
        assertFalse(keyStoreManager.isStrongBoxUsed())
    }

    @Test
    fun testKeyGenerationFallbackWhenAndroidKeyStoreUnavailable() {
        // In JVM test environment, AndroidKeyStore provider is not registered in standard JRE.
        // getOrCreateSecretKey should return null and fallback gracefully without throwing an uncaught exception.
        val secretKey = keyStoreManager.getOrCreateSecretKey()
        assertNull(secretKey)

        // Verify generateKeyStoreKey returns null on JVM runner without crashing
        val key = keyStoreManager.generateKeyStoreKey()
        assertNull(key)
    }

    @Test
    fun testFallbackBehaviorFlagTracking() {
        // Calling generateKeyStoreKey in JVM test catches Exception and handles fallback state
        keyStoreManager.generateKeyStoreKey()
        // StrongBox cannot be used on desktop JVM, so isStrongBoxUsed remains false
        assertFalse(keyStoreManager.isStrongBoxUsed())
    }
}
