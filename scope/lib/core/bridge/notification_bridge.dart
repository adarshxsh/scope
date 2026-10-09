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

  /// Cached active session token for authorized MethodChannel calls.
  String? _sessionToken;

  NotificationBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.scope.notifications');

  /// Fetches a session authorization token from the native side.
  Future<String?> getSessionToken({bool forceRefresh = false}) async {
    if (_sessionToken != null && !forceRefresh) {
      return _sessionToken;
    }
    try {
      final token = await _channel.invokeMethod<dynamic>('getSessionToken');
      if (token is String && token.isNotEmpty) {
        _sessionToken = token;
        return token;
      }
      return null;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.getSessionToken failed: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
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
        token != null ? {'token': token} : null,
      );
      if (result == null) return [];

      return result
          .whereType<Map>()
          .map((map) => AppNotification.fromMap(Map<String, dynamic>.from(map)))
          .toList();
    } on PlatformException catch (e) {
      if (e.code == 'UNAUTHORIZED') {
        final newToken = await getSessionToken(forceRefresh: true);
        if (newToken != null) {
          try {
            final retryResult = await _channel.invokeMethod<List<dynamic>>(
              'getNotifications',
              {'token': newToken},
            );
            if (retryResult == null) return [];
            return retryResult
                .whereType<Map>()
                .map((map) => AppNotification.fromMap(Map<String, dynamic>.from(map)))
                .toList();
          } on PlatformException {
            return [];
          }
        }
      }
      // Log but don't crash — the service might not be connected yet
      // ignore: avoid_print
      print('NotificationBridge.getNotifications failed: ${e.message}');
      return [];
    } on MissingPluginException {
      // Happens when running on non-Android platforms or in tests without mock
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Peeks current notifications from native queue memory without removing them.
  Future<List<AppNotification>> peekNotifications() async {
    try {
      final token = await getSessionToken();
      final result = await _channel.invokeMethod<List<dynamic>>(
        'peekNotifications',
        token != null ? {'token': token} : null,
      );
      if (result == null) return [];

      return result
          .whereType<Map>()
          .map((map) => AppNotification.fromMap(Map<String, dynamic>.from(map)))
          .toList();
    } on PlatformException catch (e) {
      if (e.code == 'UNAUTHORIZED') {
        final newToken = await getSessionToken(forceRefresh: true);
        if (newToken != null) {
          try {
            final retryResult = await _channel.invokeMethod<List<dynamic>>(
              'peekNotifications',
              {'token': newToken},
            );
            if (retryResult == null) return [];
            return retryResult
                .whereType<Map>()
                .map((map) => AppNotification.fromMap(Map<String, dynamic>.from(map)))
                .toList();
          } on PlatformException {
            return [];
          }
        }
      }
      // ignore: avoid_print
      print('NotificationBridge.peekNotifications failed: ${e.message}');
      return [];
    } on MissingPluginException {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Acknowledges and purges specific notification IDs from native queue memory.
  Future<List<String>> acknowledgeNotifications(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      final token = await getSessionToken();
      final result = await _channel.invokeMethod<List<dynamic>>(
        'acknowledgeNotifications',
        token != null ? {'token': token, 'ids': ids} : {'ids': ids},
      );
      if (result == null) return [];
      return result.whereType<String>().toList();
    } on PlatformException catch (e) {
      if (e.code == 'UNAUTHORIZED') {
        final newToken = await getSessionToken(forceRefresh: true);
        if (newToken != null) {
          try {
            final retryResult = await _channel.invokeMethod<List<dynamic>>(
              'acknowledgeNotifications',
              {'token': newToken, 'ids': ids},
            );
            if (retryResult == null) return [];
            return retryResult.whereType<String>().toList();
          } on PlatformException {
            return [];
          }
        }
      }
      // ignore: avoid_print
      print('NotificationBridge.acknowledgeNotifications failed: ${e.message}');
      return [];
    } on MissingPluginException {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Retrieves diagnostic audit metrics from native service.
  Future<Map<String, dynamic>> getAuditMetrics() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getAuditMetrics',
      );
      if (result == null) return {};
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.getAuditMetrics failed: ${e.message}');
      return {};
    } on MissingPluginException {
      return {};
    } catch (_) {
      return {};
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
    } catch (_) {
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
    } catch (_) {}
  }
}
