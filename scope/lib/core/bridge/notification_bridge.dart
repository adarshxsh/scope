/// Flutter-to-Kotlin bridge for notification data.
///
/// Communicates with [MainActivity] on the Android side via MethodChannel.
/// This is the ONLY place that talks to the native side — all other Dart
/// code goes through this class, making it easy to mock in tests.
library;

import 'package:flutter/services.dart';
import 'package:scope/core/models/notification_model.dart';

/// Represents a batch transaction of notifications returned by [NotificationBridge.fetchPendingNotifications].
class NotificationBatch {
  /// Unique transaction batch ID assigned by the native layer.
  final String batchId;

  /// List of notifications included in this batch transaction.
  final List<AppNotification> notifications;

  const NotificationBatch({
    required this.batchId,
    required this.notifications,
  });
}

/// Bridge between Flutter and the Android NotificationCollectorService.
///
/// Usage:
/// ```dart
/// final bridge = NotificationBridge();
/// final batch = await bridge.fetchPendingNotifications();
/// if (batch != null) {
///   await saveToDatabase(batch.notifications);
///   await bridge.acknowledgeNotifications(batch.batchId);
/// }
/// ```
class NotificationBridge {
  /// The MethodChannel name must match the one registered in MainActivity.kt
  final MethodChannel _channel;

  NotificationBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.scope.notifications');

  /// Fetches pending notifications as a transactional [NotificationBatch].
  ///
  /// The native side assigns a unique [NotificationBatch.batchId] and holds the batch
  /// in pending memory until [acknowledgeNotifications] is invoked after local storage persistence.
  /// Returns `null` if no notifications are available or if on non-Android platforms.
  Future<NotificationBatch?> fetchPendingNotifications({int limit = 100}) async {
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'fetchPendingNotifications',
        {'limit': limit},
      );
      if (result == null || result is! Map) return null;

      final mapResult = Map<String, dynamic>.from(result);
      final batchId = (mapResult['batchId'] ?? mapResult['transactionId']) as String?;
      final rawList = mapResult['notifications'] as List<dynamic>?;

      if (batchId == null || rawList == null) return null;

      final notifications = rawList
          .whereType<Map>()
          .map((m) => AppNotification.fromMap(Map<String, dynamic>.from(m)))
          .toList();

      return NotificationBatch(
        batchId: batchId,
        notifications: notifications,
      );
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.fetchPendingNotifications failed: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Acknowledges successful local persistence of a transaction batch.
  ///
  /// Signals the native layer to safely purge the batch from pending memory.
  /// Returns `true` if acknowledged successfully, `false` otherwise.
  Future<bool> acknowledgeNotifications(String batchId) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'acknowledgeNotifications',
        {'batchId': batchId, 'transactionId': batchId},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.acknowledgeNotifications failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Monitors the current active queue length without mutating state or removing items.
  Future<int> peekNotificationCount() async {
    try {
      final result = await _channel.invokeMethod<int>('peekNotificationCount');
      return result ?? 0;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.peekNotificationCount failed: ${e.message}');
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  /// Fetches pending notifications, executes local persistence via [onSave],
  /// and acknowledges the transaction batch ONLY if persistence completes successfully.
  ///
  /// If [onSave] throws an error, acknowledgement is omitted, allowing the
  /// native 30-second expiry worker to return the batch to the active queue.
  Future<List<AppNotification>> fetchAndAcknowledge({
    required Future<void> Function(List<AppNotification> notifications) onSave,
  }) async {
    final batch = await fetchPendingNotifications();
    if (batch == null || batch.notifications.isEmpty) return [];

    await onSave(batch.notifications);
    await acknowledgeNotifications(batch.batchId);
    return batch.notifications;
  }

  /// Legacy single-shot notification drain.
  ///
  /// Deprecated in favor of two-phase transactional IPC ([fetchPendingNotifications]
  /// and [acknowledgeNotifications]).
  Future<List<AppNotification>> getNotifications() async {
    try {
      final batch = await fetchPendingNotifications();
      if (batch != null) {
        await acknowledgeNotifications(batch.batchId);
        return batch.notifications;
      }

      final result = await _channel.invokeMethod<List<dynamic>>(
        'getNotifications',
      );
      if (result == null) return [];

      return result
          .whereType<Map>()
          .map((map) => AppNotification.fromMap(Map<String, dynamic>.from(map)))
          .toList();
    } on PlatformException catch (e) {
      // Log but don't crash — the service might not be connected yet
      // ignore: avoid_print
      print('NotificationBridge.getNotifications failed: ${e.message}');
      return [];
    } on MissingPluginException {
      // Happens when running on non-Android platforms or in tests without mock
      return [];
    }
  }

  /// Checks if the notification listener service has been granted access.
  ///
  /// Returns false if the check fails (e.g., on non-Android platforms).
  Future<bool> isListenerEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isListenerEnabled');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the Android system settings page for notification listener access.
  ///
  /// The user must manually toggle permission for this app.
  Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod<void>('openNotificationSettings');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.openNotificationSettings failed: ${e.message}');
    } on MissingPluginException {
      // Not on Android — nothing to do
    }
  }
}
