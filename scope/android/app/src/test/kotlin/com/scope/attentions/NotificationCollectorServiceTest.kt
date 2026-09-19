package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class NotificationCollectorServiceTest {

    @Before
    fun setUp() {
        NotificationCollectorService.resetForTesting()
    }

    @Test
    fun testGetSessionTokenGeneratesAndCachesToken() {
        val token1 = NotificationCollectorService.getSessionToken()
        assertNotNull(token1)
        assertTrue(token1.isNotEmpty())

        val token2 = NotificationCollectorService.getSessionToken()
        assertEquals(token1, token2)
    }

    @Test
    fun testValidateToken() {
        val validToken = NotificationCollectorService.getSessionToken()
        assertTrue(NotificationCollectorService.validateToken(validToken))
        assertFalse(NotificationCollectorService.validateToken("invalid-token"))
        assertFalse(NotificationCollectorService.validateToken(""))
        assertFalse(NotificationCollectorService.validateToken(null))
    }

    @Test
    fun testPeekQueueRequiresValidToken() {
        val token = NotificationCollectorService.getSessionToken()
        val items = NotificationCollectorService.peekQueue(token)
        assertNotNull(items)

        try {
            NotificationCollectorService.peekQueue("bad-token")
            fail("Expected SecurityException on invalid token")
        } catch (e: SecurityException) {
            // Expected
        }

        val metrics = NotificationCollectorService.getAuditMetrics()
        assertEquals(1L, metrics["authorizedAccessCount"])
        assertEquals(1L, metrics["unauthorizedAccessCount"])
    }

    @Test
    fun testAcknowledgeQueueRequiresValidToken() {
        val token = NotificationCollectorService.getSessionToken()
        val ackIds = NotificationCollectorService.acknowledgeQueue(token, listOf("notif_1"))
        assertTrue(ackIds.isEmpty())

        try {
            NotificationCollectorService.acknowledgeQueue(null, listOf("notif_1"))
            fail("Expected SecurityException on null token")
        } catch (e: SecurityException) {
            // Expected
        }

        val metrics = NotificationCollectorService.getAuditMetrics()
        assertEquals(1L, metrics["authorizedAccessCount"])
        assertEquals(1L, metrics["unauthorizedAccessCount"])
    }

    @Test
    fun testDrainQueueRequiresValidToken() {
        val token = NotificationCollectorService.getSessionToken()
        val items = NotificationCollectorService.drainQueue(token)
        assertTrue(items.isEmpty())

        try {
            NotificationCollectorService.drainQueue("invalid-token")
            fail("Expected SecurityException on invalid token")
        } catch (e: SecurityException) {
            // Expected
        }

        val metrics = NotificationCollectorService.getAuditMetrics()
        assertEquals(1L, metrics["authorizedAccessCount"])
        assertEquals(1L, metrics["unauthorizedAccessCount"])
    }
}
