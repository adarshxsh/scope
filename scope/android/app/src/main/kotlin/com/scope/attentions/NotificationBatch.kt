package com.scope.attentions

/**
 * Data class representing a batch transaction of notifications sent to Flutter.
 *
 * Each batch is assigned a unique [batchId] and stored in native memory until
 * Flutter acknowledges local database persistence via MethodChannel or
 * the 30-second expiry timeout occurs and rolls the items back to the active queue.
 */
data class NotificationBatch(
    val batchId: String,
    val notifications: List<NotificationData>,
    val timestamp: Long = System.currentTimeMillis()
) {
    /**
     * Converts to a HashMap for MethodChannel serialization.
     */
    fun toMap(): HashMap<String, Any?> {
        return hashMapOf(
            "batchId" to batchId,
            "transactionId" to batchId,
            "notifications" to notifications.map { it.toMap() }
        )
    }
}
