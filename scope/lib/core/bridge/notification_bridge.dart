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
  String? _sessionToken;

  NotificationBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.scope.notifications');

  /// Fetches the active dynamic session token from the native side.
  Future<String?> getSessionToken() async {
    if (_sessionToken != null) return _sessionToken;
    try {
      _sessionToken = await _channel.invokeMethod<String>('getSessionToken');
      return _sessionToken;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.getSessionToken failed: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Non-destructively inspects the pending notification queue on the Android side.
  ///
  /// Returns a list of [AppNotification] objects currently in the native queue.
  /// Does NOT modify or remove items from the native queue.
  Future<List<AppNotification>> peekNotifications() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'peekNotifications',
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

  /// Explicitly acknowledges receipt of notifications by ID and clears them from the native queue.
  ///
  /// Requires a valid session token to perform queue mutations on the native side.
  Future<bool> acknowledgeNotifications(List<String> ids) async {
    if (ids.isEmpty) return true;
    final token = await getSessionToken();
    try {
      final result = await _channel.invokeMethod<bool>(
        'acknowledgeNotifications',
        {
          'token': token,
          'ids': ids,
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

  /// Returns a list of [AppNotification] objects captured on the Android side.
  ///
  /// Backwards-compatible wrapper that delegates to [peekNotifications].
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
