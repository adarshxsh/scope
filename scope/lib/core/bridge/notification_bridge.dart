/// Flutter-to-Kotlin bridge for notification data.
///
/// Communicates with [MainActivity] on the Android side via MethodChannel.
/// This is the ONLY place that talks to the native side — all other Dart
/// code goes through this class, making it easy to mock in tests.
library;

import 'package:flutter/services.dart';
import 'package:scope/core/models/app_info.dart';
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

  /// Gets the list of package IDs blacklisted from ingestion.
  Future<List<String>> getExcludedPackages() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getExcludedPackages');
      if (result == null) return [];
      return result.map((e) => e.toString()).toList();
    } on PlatformException {
      return [];
    } on MissingPluginException {
      return [];
    }
  }

  /// Updates the list of package IDs blacklisted from ingestion.
  Future<bool> setExcludedPackages(List<String> packages) async {
    try {
      final result = await _channel.invokeMethod<bool>('setExcludedPackages', {
        'packages': packages,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Checks whether system status/media category filtering is enabled.
  Future<bool> getExcludeSystemCategories() async {
    try {
      final result = await _channel.invokeMethod<bool>('getExcludeSystemCategories');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Updates whether system status/media category filtering is enabled.
  Future<bool> setExcludeSystemCategories(bool exclude) async {
    try {
      final result = await _channel.invokeMethod<bool>('setExcludeSystemCategories', {
        'exclude': exclude,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Retrieves installed applications for App Exclusion controls in Settings.
  Future<List<AppInfo>> getInstalledApps() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getInstalledApps');
      if (result == null) return _defaultMockApps();

      return result
          .whereType<Map>()
          .map((map) => AppInfo.fromMap(Map<String, dynamic>.from(map)))
          .toList();
    } on PlatformException {
      return _defaultMockApps();
    } on MissingPluginException {
      return _defaultMockApps();
    }
  }

  List<AppInfo> _defaultMockApps() {
    return const [
      AppInfo(packageName: 'com.chase.sig.android', appName: 'Chase Mobile'),
      AppInfo(packageName: 'com.paypal.android.p2pmobile', appName: 'PayPal'),
      AppInfo(packageName: 'com.google.android.apps.authenticator2', appName: 'Google Authenticator'),
      AppInfo(packageName: 'com.whatsapp', appName: 'WhatsApp'),
      AppInfo(packageName: 'com.instagram.android', appName: 'Instagram'),
      AppInfo(packageName: 'com.google.android.youtube', appName: 'YouTube'),
      AppInfo(packageName: 'com.spotify.music', appName: 'Spotify'),
      AppInfo(packageName: 'com.slack', appName: 'Slack'),
    ];
  }
}

