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

  /// Drains the notification queue from the Android side.
  ///
  /// Returns a list of [AppNotification] objects captured since the last call.
  /// Returns an empty list if the service isn't running or no new notifications.
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

  /// Sets the package exclusion blacklist on native Android side.
  Future<bool> setPackageExclusionList(List<String> packages) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'setPackageExclusionList',
        {'packages': packages},
      );
      return result ?? true;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.setPackageExclusionList failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Sets category exclusion rules on native Android side.
  Future<bool> setCategoryExclusionRules(List<String> categories) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'setCategoryExclusionRules',
        {'categories': categories},
      );
      return result ?? true;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.setCategoryExclusionRules failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Gets the current package exclusion list from native SharedPreferences.
  Future<List<String>> getPackageExclusionList() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getPackageExclusionList',
      );
      if (result == null) return [];
      return result.whereType<String>().toList();
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.getPackageExclusionList failed: ${e.message}');
      return [];
    } on MissingPluginException {
      return [];
    }
  }

  /// Gets current category exclusion rules from native SharedPreferences.
  Future<List<String>> getCategoryExclusionRules() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getCategoryExclusionRules',
      );
      if (result == null) return [];
      return result.whereType<String>().toList();
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.getCategoryExclusionRules failed: ${e.message}');
      return [];
    } on MissingPluginException {
      return [];
    }
  }

  /// Gets list of installed launchable apps from native PackageManager.
  Future<List<Map<String, String>>> getInstalledApps() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getInstalledApps',
      );
      if (result == null) return [];
      return result
          .whereType<Map>()
          .map((map) => Map<String, String>.from(map))
          .toList();
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.getInstalledApps failed: ${e.message}');
      return [];
    } on MissingPluginException {
      return [];
    }
  }
}
