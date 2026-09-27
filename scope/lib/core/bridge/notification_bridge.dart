/// Flutter-to-Kotlin bridge for notification data.
///
/// Communicates with [MainActivity] on the Android side via EventChannel
/// for streaming real-time notifications and MethodChannel for settings.
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
/// bridge.notificationStream.listen((notification) { ... });
/// ```
class NotificationBridge {
  /// The MethodChannel name must match the one registered in MainActivity.kt
  final MethodChannel _channel;

  /// The EventChannel name must match the one registered in MainActivity.kt
  final EventChannel _eventChannel;

  Stream<AppNotification>? _notificationStream;

  NotificationBridge({
    MethodChannel? channel,
    EventChannel? eventChannel,
  })  : _channel = channel ?? const MethodChannel('com.scope.notifications'),
        _eventChannel =
            eventChannel ?? const EventChannel('com.scope.notifications/stream');

  /// Real-time stream of incoming notifications streamed directly from
  /// the Android NotificationCollectorService via EventChannel.
  Stream<AppNotification> get notificationStream {
    _notificationStream ??= _eventChannel
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .map((event) => AppNotification.fromMap(Map<String, dynamic>.from(event as Map)));
    return _notificationStream!;
  }

  /// Drains the notification queue from the Android side.
  ///
  /// Deprecated: MethodChannel polling is replaced by real-time [notificationStream].
  @Deprecated('Use notificationStream instead')
  Future<List<AppNotification>> getNotifications() async {
    try {
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

