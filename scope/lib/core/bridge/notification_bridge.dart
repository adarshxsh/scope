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

  NotificationBridge({MethodChannel? channel, String? sessionToken})
    : _channel = channel ?? const MethodChannel('com.scope.notifications'),
      _sessionToken = sessionToken;

  /// Retrieves or initializes the session token from MainActivity.
  Future<String?> getSessionToken() async {
    if (_sessionToken != null) return _sessionToken;
    try {
      _sessionToken = await _channel.invokeMethod<String>('getSessionToken');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.getSessionToken failed: ${e.message}');
    } on MissingPluginException {
      // Happens when running on non-Android platforms or in tests without mock
    }
    return _sessionToken;
  }

  /// Drains the notification queue from the Android side.
  ///
  /// Returns a list of [AppNotification] objects captured since the last call.
  /// Returns an empty list if the service isn't running or no new notifications.
  Future<List<AppNotification>> getNotifications() async {
    try {
      final token = await getSessionToken();
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getNotifications',
        <String, dynamic>{'token': token},
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
      final token = await getSessionToken();
      final result = await _channel.invokeMethod<bool>(
        'isListenerEnabled',
        <String, dynamic>{'token': token},
      );
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
      final token = await getSessionToken();
      await _channel.invokeMethod<void>(
        'openNotificationSettings',
        <String, dynamic>{'token': token},
      );
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.openNotificationSettings failed: ${e.message}');
    } on MissingPluginException {
      // Not on Android — nothing to do
    }
  }
}
