package com.scope.attentions

import org.junit.Assert.*
import org.junit.Test

class KeyStoreHelperTest {

    @Test
    fun testKeyStoreConstants() {
        assertEquals("AndroidKeyStore", KeyStoreHelper.KEYSTORE_PROVIDER)
        assertEquals("scope_master_key", KeyStoreHelper.MASTER_KEY_ALIAS)
    }

    @Test
    fun testHexConversion() {
        val bytes = byteArrayOf(0x00.toByte(), 0x0F.toByte(), 0x10.toByte(), 0xFF.toByte())
        val sb = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            sb.append(String.format("%02x", b))
        }
        val hex = sb.toString()
        assertEquals("000f10ff", hex)
        assertEquals(8, hex.length)
    }
}
