/// Flutter-to-Kotlin bridge for notification data.
///
/// Communicates with [MainActivity] on the Android side via MethodChannel.
/// This is the ONLY place that talks to the native side — all other Dart
/// code goes through this class, making it easy to mock in tests.
library;

import 'package:flutter/services.dart';
import 'package:scope/core/models/notification_model.dart';

/// Bridge between Flutter and the Android NotificationCollectorService.
///
/// Usage:
/// ```dart
/// final bridge = NotificationBridge();
/// final batch = await bridge.getNotifications();
/// await bridge.acknowledgeNotifications(batch.batchId);
/// ```
class NotificationBatch {
  final String batchId;
  final List<AppNotification> notifications;

  const NotificationBatch({
    required this.batchId,
    required this.notifications,
  });

  bool get isEmpty => notifications.isEmpty;
  bool get isNotEmpty => notifications.isNotEmpty;
}

class NotificationBridge {
  /// The MethodChannel name must match the one registered in MainActivity.kt
  final MethodChannel _channel;

  NotificationBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.scope.notifications');

  /// Fetches a tagged notification batch from the Android side.
  ///
  /// Returns a [NotificationBatch] object containing a batch identifier and list
  /// of [AppNotification] objects.
  Future<NotificationBatch> getNotifications() async {
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'getNotifications',
      );
      if (result == null) {
        return const NotificationBatch(batchId: '', notifications: []);
      }

      if (result is Map) {
        final batchId = (result['batchId'] as String?) ?? '';
        final rawList = (result['notifications'] as List?) ?? [];
        final notifications = rawList
            .whereType<Map>()
            .map((map) => AppNotification.fromMap(Map<String, dynamic>.from(map)))
            .toList();
        return NotificationBatch(batchId: batchId, notifications: notifications);
      } else if (result is List) {
        final notifications = result
            .whereType<Map>()
            .map((map) => AppNotification.fromMap(Map<String, dynamic>.from(map)))
            .toList();
        return NotificationBatch(batchId: '', notifications: notifications);
      }

      return const NotificationBatch(batchId: '', notifications: []);
    } on PlatformException catch (e) {
      // Log but don't crash — the service might not be connected yet
      // ignore: avoid_print
      print('NotificationBridge.getNotifications failed: ${e.message}');
      return const NotificationBatch(batchId: '', notifications: []);
    } on MissingPluginException {
      // Happens when running on non-Android platforms or in tests without mock
      return const NotificationBatch(batchId: '', notifications: []);
    }
  }

  /// Confirms successful persistence of a notification batch on the Android side.
  Future<bool> acknowledgeNotifications(String batchId) async {
    if (batchId.isEmpty) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'acknowledgeNotifications',
        {'batchId': batchId},
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

  /// Non-destructive inspection of pending notifications.
  Future<List<AppNotification>> peekQueue() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('peekQueue');
      if (result == null) return [];

      return result
          .whereType<Map>()
          .map((map) => AppNotification.fromMap(Map<String, dynamic>.from(map)))
          .toList();
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.peekQueue failed: ${e.message}');
      return [];
    } on MissingPluginException {
      return [];
    }
  }

  /// Returns current pending queue depth.
  Future<int> getQueueSize() async {
    try {
      final result = await _channel.invokeMethod<int>('getQueueSize');
      return result ?? 0;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.getQueueSize failed: ${e.message}');
      return 0;
    } on MissingPluginException {
      return 0;
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
