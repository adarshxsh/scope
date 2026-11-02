package com.scope.attentions

import android.content.SharedPreferences
import org.junit.Assert.*
import org.junit.Test

class SecurityKeyManagerTest {

    private class MockSharedPreferences : SharedPreferences {
        private val map = mutableMapOf<String, String>()

        override fun getString(key: String?, defValue: String?): String? {
            return map[key] ?: defValue
        }

        override fun edit(): SharedPreferences.Editor = MockEditor()

        private inner class MockEditor : SharedPreferences.Editor {
            private val tempMap = mutableMapOf<String, String>()

            override fun putString(key: String?, value: String?): SharedPreferences.Editor {
                if (key != null && value != null) tempMap[key] = value
                return this
            }

            override fun apply() {
                map.putAll(tempMap)
            }

            override fun commit(): Boolean {
                map.putAll(tempMap)
                return true
            }

            override fun putBoolean(key: String?, value: Boolean) = this
            override fun putFloat(key: String?, value: Float) = this
            override fun putInt(key: String?, value: Int) = this
            override fun putLong(key: String?, value: Long) = this
            override fun putStringSet(key: String?, values: MutableSet<String>?) = this
            override fun remove(key: String?) = this
            override fun clear() = this
        }

        override fun contains(key: String?): Boolean = map.containsKey(key)
        override fun getAll(): MutableMap<String, *> = map
        override fun getBoolean(key: String?, defValue: Boolean): Boolean = defValue
        override fun getFloat(key: String?, defValue: Float): Float = defValue
        override fun getInt(key: String?, defValue: Int): Int = defValue
        override fun getLong(key: String?, defValue: Long): Long = defValue
        override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? = defValues
        override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
        override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
    }

    @Test
    fun testGetOrCreateDatabaseKeyReturnsValidHexKey() {
        val mockPrefs = MockSharedPreferences()
        val keyManager = SecurityKeyManager(customPrefs = mockPrefs)

        val key1 = keyManager.getOrCreateDatabaseKey()
        assertNotNull(key1)
        assertEquals(64, key1.length)

        val key2 = keyManager.getOrCreateDatabaseKey()
        assertEquals(key1, key2)
    }
}
