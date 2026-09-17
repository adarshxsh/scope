package com.scope.attentions

import android.content.SharedPreferences
import org.junit.Assert.*
import org.junit.Test
import java.lang.reflect.InvocationHandler
import java.lang.reflect.Proxy

class SecurityKeyManagerTest {

    private fun createFakeSharedPreferences(): SharedPreferences {
        val prefsMap = mutableMapOf<String, Any?>()

        val editorProxy = Proxy.newProxyInstance(
            SharedPreferences.Editor::class.java.classLoader,
            arrayOf(SharedPreferences.Editor::class.java),
            object : InvocationHandler {
                override fun invoke(proxy: Any?, method: java.lang.reflect.Method, args: Array<out Any>?): Any? {
                    when (method.name) {
                        "putString" -> {
                            val key = args!![0] as String
                            val value = args[1]
                            prefsMap[key] = value
                            return proxy
                        }
                        "apply", "commit" -> return true
                        else -> return proxy
                    }
                }
            }
        ) as SharedPreferences.Editor

        val prefsProxy = Proxy.newProxyInstance(
            SharedPreferences::class.java.classLoader,
            arrayOf(SharedPreferences::class.java),
            object : InvocationHandler {
                override fun invoke(proxy: Any?, method: java.lang.reflect.Method, args: Array<out Any>?): Any? {
                    when (method.name) {
                        "getString" -> {
                            val key = args!![0] as String
                            val default = args[1] as String?
                            return prefsMap[key] as? String ?: default
                        }
                        "edit" -> return editorProxy
                        else -> return null
                    }
                }
            }
        ) as SharedPreferences

        return prefsProxy
    }

    @Test
    fun testGetOrCreateDatabasePassphrase_GeneratesAndPersistsPassphrase() {
        val prefs = createFakeSharedPreferences()
        val manager = SecurityKeyManager(context = null, customPrefs = prefs)

        val passphrase1 = manager.getOrCreateDatabasePassphrase()
        assertNotNull(passphrase1)
        assertEquals(64, passphrase1.length)

        val passphrase2 = manager.getOrCreateDatabasePassphrase()
        assertEquals("Passphrase should be persisted and deterministic across calls", passphrase1, passphrase2)
    }

    @Test
    fun testGetOrCreateMasterKey_ReturnsValidAESKey() {
        val prefs = createFakeSharedPreferences()
        val manager = SecurityKeyManager(context = null, customPrefs = prefs)

        val key = manager.getOrCreateMasterKey()
        assertNotNull(key)
        assertEquals("AES", key.algorithm)
    }
}
