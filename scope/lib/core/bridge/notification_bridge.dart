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
/// final notifications = await bridge.getNotifications();
/// ```
class NotificationBridge {
  /// The MethodChannel name must match the one registered in MainActivity.kt
  final MethodChannel _channel;

  NotificationBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.scope.notifications');

  /// Peeks buffered notifications from the Android side without removing them.
  ///
  /// Returns a list of [AppNotification] objects currently in native memory.
  /// Returns an empty list if the service isn't running or queue is empty.
  Future<List<AppNotification>> peekNotifications({int? limit}) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'peekNotifications',
        limit != null ? {'limit': limit} : null,
      );
      if (result == null) return [];

      return result
          .whereType<Map>()
          .map((map) => AppNotification.fromMap(Map<String, dynamic>.from(map)))
          .toList();
    } on PlatformException catch (e) {
      // Log but don't crash — the service might not be connected yet
      // ignore: avoid_print
      print('NotificationBridge.peekNotifications failed: ${e.message}');
      return [];
    } on MissingPluginException {
      // Happens when running on non-Android platforms or in tests without mock
      return [];
    }
  }

  /// Explicitly acknowledges notifications by their IDs to prune them from native memory.
  ///
  /// Returns true if acknowledgment was acknowledged by native side, false on failure.
  Future<bool> ackNotifications(List<String> ids) async {
    if (ids.isEmpty) return true;
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'ackNotifications',
        {'ids': ids},
      );
      return result != null;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.ackNotifications failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Drains the notification queue from the Android side.
  ///
  /// Deprecated in favor of [peekNotifications] and [ackNotifications].
  @Deprecated('Use peekNotifications and ackNotifications instead')
  Future<List<AppNotification>> getNotifications() async {
    return peekNotifications();
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
