package com.scope.attentions

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * Android service that captures all incoming notifications.
 *
 * Extends [NotificationListenerService] which requires the user to manually
 * grant "Notification access" in system Settings.
 *
 * Captured notifications are streamed directly to Flutter via [MainActivity]'s
 * EventChannel handler with zero static queue retention in Kotlin memory.
 */
class NotificationCollectorService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotifCollector"

        /** Active instance reference while service is connected to OS. */
        var instance: NotificationCollectorService? = null
            private set

        /** Counter for generating simple unique IDs within a session. */
        private var idCounter = 0L

        /** Listener callback set by MainActivity to stream notifications to Flutter EventChannel. */
        var listener: ((NotificationData) -> Unit)? = null

        /**
         * Triggers direct sync of active notifications from the Android notification panel
         * to the active stream subscriber without queue retention.
         */
        fun syncActiveNotifications() {
            instance?.syncActiveNotificationsInternal()
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        Log.i(TAG, "NotificationCollectorService connected")
        if (listener != null) {
            syncActiveNotificationsInternal()
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        if (instance == this) {
            instance = null
        }
        Log.w(TAG, "NotificationCollectorService disconnected")
    }

    override fun onDestroy() {
        super.onDestroy()
        if (instance == this) {
            instance = null
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        emitNotification(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        // Log for now; future phases may track dismissed notifications
        val removedTitle = sbn.notification.extras?.getCharSequence("android.title")?.toString()
        Log.d(TAG, "Removed: ${sbn.packageName} - ${NotificationRedactor.redactTitle(removedTitle)}")
    }

    private fun syncActiveNotificationsInternal() {
        try {
            val activeNotifs = activeNotifications
            if (activeNotifs != null) {
                Log.d(TAG, "Syncing ${activeNotifs.size} existing notifications from panel directly to stream")
                for (sbn in activeNotifs) {
                    emitNotification(sbn)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error fetching active notifications for stream sync", e)
        }
    }

    private fun emitNotification(sbn: StatusBarNotification) {
        try {
            val extras = sbn.notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = sbn.isOngoing
            val packageName = sbn.packageName ?: "unknown"

            val data = NotificationData(
                id = "notif_${++idCounter}",
                packageName = packageName,
                title = title,
                content = text,
                timestamp = if (sbn.postTime > 0) sbn.postTime else System.currentTimeMillis(),
                category = sbn.notification.category,
                isOngoing = isOngoing
            )

            val currentListener = listener
            if (currentListener != null) {
                currentListener.invoke(data)
                Log.d(TAG, "Streamed: ${data.packageName} - ${NotificationRedactor.redactTitle(data.title)}")
            } else {
                Log.d(TAG, "No active EventSink subscriber; passed through ${data.packageName}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing notification for stream", e)
        }
    }
}
