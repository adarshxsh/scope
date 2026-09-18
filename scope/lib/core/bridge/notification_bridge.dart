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
  String? _authToken;

  NotificationBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.scope.notifications');

  /// Exposes the current cached session authorization token (for diagnostics/tests).
  String? get currentAuthToken => _authToken;

  /// Resets cached authorization state (e.g., for testing fallback recovery).
  void resetAuthToken() {
    _authToken = null;
  }

  /// Internal audit log wrapper without cleartext PII.
  void _logAudit(String message) {
    // ignore: avoid_print
    print('[NotificationBridge Audit] $message');
  }

  /// Fetches or returns cached session authorization token from MainActivity.
  Future<String?> _getOrFetchToken({bool forceRefresh = false}) async {
    if (!forceRefresh && _authToken != null) return _authToken;
    try {
      final token = await _channel.invokeMethod<String>('getAuthToken');
      _authToken = token;
      _logAudit('Session auth token established');
      return _authToken;
    } on PlatformException catch (e) {
      _logAudit('Failed to fetch auth token: ${e.code} - ${e.message}');
      return null;
    } on MissingPluginException {
      // Non-Android or test environment without mock
      return null;
    } catch (_) {
      // Handles mock channels returning non-String types gracefully
      return null;
    }
  }

  /// Drains the notification queue from the Android side.
  ///
  /// Returns a list of [AppNotification] objects captured since the last call.
  /// Returns an empty list if the service isn't running, rate limited, or no new notifications.
  Future<List<AppNotification>> getNotifications() async {
    try {
      final token = await _getOrFetchToken();
      final Map<String, dynamic> args = {};
      if (token != null) {
        args['authToken'] = token;
      }

      final result = await _invokeGetNotifications(args);
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'UNAUTHORIZED') {
        _logAudit('Unauthorized drain attempt detected. Retrying token handshake...');
        _authToken = null;
        final newToken = await _getOrFetchToken(forceRefresh: true);
        if (newToken != null) {
          try {
            return await _invokeGetNotifications({'authToken': newToken});
          } on PlatformException catch (retryErr) {
            _logAudit('Retry after token refresh failed: ${retryErr.message}');
            return [];
          }
        }
      } else if (e.code == 'RATE_LIMITED') {
        _logAudit('Rate limit enforced by native collector. Backing off.');
        return [];
      } else {
        _logAudit('NotificationBridge.getNotifications failed: ${e.message}');
      }
      return [];
    } on MissingPluginException {
      // Happens when running on non-Android platforms or in tests without mock
      return [];
    }
  }

  Future<List<AppNotification>> _invokeGetNotifications(Map<String, dynamic> args) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'getNotifications',
      args.isNotEmpty ? args : null,
    );
    if (result == null) return [];

    return result
        .whereType<Map>()
        .map((map) => AppNotification.fromMap(Map<String, dynamic>.from(map)))
        .toList();
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
