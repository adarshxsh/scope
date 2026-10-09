package com.scope.attentions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NotificationCollectorServiceTest {

    @Test
    fun testListenerRegistration() {
        assertNull(NotificationCollectorService.listener)
        var receivedData: NotificationData? = null
        NotificationCollectorService.listener = { data ->
            receivedData = data
        }
        val testData = NotificationData(
            id = "test_1",
            packageName = "com.test.app",
            title = "Test",
            content = "Content",
            timestamp = 1000L,
            category = null,
            isOngoing = false
        )
        NotificationCollectorService.listener?.invoke(testData)
        assertEquals("test_1", receivedData?.id)
        NotificationCollectorService.listener = null
    }
}
