/// Flutter-to-Kotlin bridge for notification data.
///
/// Communicates with [MainActivity] on the Android side via MethodChannel.
/// Uses a two-phase transactional acknowledgment protocol and session token
/// caller validation to prevent notification data loss.
library;

import 'package:flutter/services.dart';
import 'package:scope/core/models/notification_model.dart';

/// Bridge between Flutter and the Android NotificationCollectorService.
class NotificationBridge {
  /// The MethodChannel name must match the one registered in MainActivity.kt
  final MethodChannel _channel;

  /// Session token for authenticating calls with the native service.
  final String sessionToken;

  /// Tracks the batch ID of the last fetched transactional notification batch.
  String? _lastBatchId;

  String? get lastBatchId => _lastBatchId;

  NotificationBridge({
    MethodChannel? channel,
    this.sessionToken = 'scope-session-token',
  }) : _channel = channel ?? const MethodChannel('com.scope.notifications');

  /// Fetches pending notifications from the Android side in a transactional state.
  ///
  /// Returns a list of [AppNotification] objects captured since the last call.
  /// Retains returned items in native memory until explicitly acknowledged.
  Future<List<AppNotification>> getNotifications() async {
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'getNotifications',
        {'token': sessionToken},
      );
      if (result == null) return [];

      List<dynamic> list;
      if (result is Map) {
        _lastBatchId = result['batchId'] as String?;
        list = (result['notifications'] as List<dynamic>?) ?? [];
      } else if (result is List) {
        list = result;
      } else {
        return [];
      }

      return list
          .whereType<Map>()
          .map((map) => AppNotification.fromMap(Map<String, dynamic>.from(map)))
          .toList();
    } on PlatformException catch (e) {
      // Log but don't crash — the service might not be connected or unauthorized
      // ignore: avoid_print
      print('NotificationBridge.getNotifications failed: ${e.message}');
      return [];
    } on MissingPluginException {
      // Happens when running on non-Android platforms or in tests without mock
      return [];
    }
  }

  /// Sends explicit processing acknowledgment to the native service for
  /// successfully stored notification IDs, triggering their removal.
  Future<bool> acknowledgeNotifications(
    List<String> notificationIds, {
    String? batchId,
  }) async {
    if (notificationIds.isEmpty) return true;

    try {
      final result = await _channel.invokeMethod<bool>(
        'acknowledgeNotifications',
        {
          'token': sessionToken,
          'notificationIds': notificationIds,
          'batchId': batchId ?? _lastBatchId,
        },
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

  /// Non-destructively peeks at current pending notifications in the queue.
  Future<List<AppNotification>> peekNotifications() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'peekNotifications',
        {'token': sessionToken},
      );
      if (result == null) return [];

      return result
          .whereType<Map>()
          .map((map) => AppNotification.fromMap(Map<String, dynamic>.from(map)))
          .toList();
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.peekNotifications failed: ${e.message}');
      return [];
    } on MissingPluginException {
      return [];
    }
  }

  /// Retrieves current pending queue size without modifying queue state.
  Future<int> getQueueSize() async {
    try {
      final result = await _channel.invokeMethod<int>(
        'getQueueSize',
        {'token': sessionToken},
      );
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
