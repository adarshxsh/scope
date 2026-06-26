package com.scope.attentions

/**
 * Lightweight data class representing a captured Android notification.
 *
 * This mirrors the Dart [AppNotification] model. Data flows:
 *   Android NotificationListenerService → NotificationData → MethodChannel → Dart AppNotification
 *
 * All fields are kept nullable-safe with sensible defaults so that
 * partially-populated notifications (e.g., missing title) don't crash the pipeline.
 */
data class NotificationData(
    val id: String,
    val packageName: String,
    val title: String,
    val content: String,
    val timestamp: Long,
    val category: String?,
    val isOngoing: Boolean
) {
    /**
     * Converts to a HashMap for MethodChannel serialization.
     * Keys match the Dart [AppNotification.fromMap] expectations.
     */
    fun toMap(): HashMap<String, Any?> {
        return hashMapOf(
            "id" to id,
            "packageName" to packageName,
            "title" to title,
            "content" to content,
            "timestamp" to timestamp,
            "category" to category,
            "isOngoing" to isOngoing
        )
    }
}
