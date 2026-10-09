/// Flutter-to-Kotlin bridge for notification data.
///
/// Communicates with [MainActivity] on the Android side via MethodChannel.
/// This is the ONLY place that talks to the native side — all other Dart
/// code goes through this class, making it easy to mock in tests.
library;

import 'package:flutter/services.dart';
import 'package:scope/core/models/notification_model.dart';

/// Data model representing native ingestion guardrails configuration.
class IngestionGuardrails {
  final List<String> blockedPackages;
  final List<String> allowedPackages;
  final bool isWhitelistMode;
  final bool excludeOtp;
  final bool excludeFinance;
  final bool excludeHealth;
  final bool excludeSystemServices;
  final int droppedCount;

  const IngestionGuardrails({
    this.blockedPackages = const [],
    this.allowedPackages = const [],
    this.isWhitelistMode = false,
    this.excludeOtp = true,
    this.excludeFinance = true,
    this.excludeHealth = false,
    this.excludeSystemServices = true,
    this.droppedCount = 0,
  });

  factory IngestionGuardrails.fromMap(Map<String, dynamic> map) {
    return IngestionGuardrails(
      blockedPackages: (map['blockedPackages'] as List?)?.cast<String>() ?? const [],
      allowedPackages: (map['allowedPackages'] as List?)?.cast<String>() ?? const [],
      isWhitelistMode: map['isWhitelistMode'] as bool? ?? false,
      excludeOtp: map['excludeOtp'] as bool? ?? true,
      excludeFinance: map['excludeFinance'] as bool? ?? true,
      excludeHealth: map['excludeHealth'] as bool? ?? false,
      excludeSystemServices: map['excludeSystemServices'] as bool? ?? true,
      droppedCount: map['droppedCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'blockedPackages': blockedPackages,
      'allowedPackages': allowedPackages,
      'isWhitelistMode': isWhitelistMode,
      'excludeOtp': excludeOtp,
      'excludeFinance': excludeFinance,
      'excludeHealth': excludeHealth,
      'excludeSystemServices': excludeSystemServices,
      'droppedCount': droppedCount,
    };
  }

  IngestionGuardrails copyWith({
    List<String>? blockedPackages,
    List<String>? allowedPackages,
    bool? isWhitelistMode,
    bool? excludeOtp,
    bool? excludeFinance,
    bool? excludeHealth,
    bool? excludeSystemServices,
    int? droppedCount,
  }) {
    return IngestionGuardrails(
      blockedPackages: blockedPackages ?? this.blockedPackages,
      allowedPackages: allowedPackages ?? this.allowedPackages,
      isWhitelistMode: isWhitelistMode ?? this.isWhitelistMode,
      excludeOtp: excludeOtp ?? this.excludeOtp,
      excludeFinance: excludeFinance ?? this.excludeFinance,
      excludeHealth: excludeHealth ?? this.excludeHealth,
      excludeSystemServices: excludeSystemServices ?? this.excludeSystemServices,
      droppedCount: droppedCount ?? this.droppedCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IngestionGuardrails &&
          runtimeType == other.runtimeType &&
          _listEquals(blockedPackages, other.blockedPackages) &&
          _listEquals(allowedPackages, other.allowedPackages) &&
          isWhitelistMode == other.isWhitelistMode &&
          excludeOtp == other.excludeOtp &&
          excludeFinance == other.excludeFinance &&
          excludeHealth == other.excludeHealth &&
          excludeSystemServices == other.excludeSystemServices &&
          droppedCount == other.droppedCount;

  @override
  int get hashCode =>
      Object.hashAll(blockedPackages) ^
      Object.hashAll(allowedPackages) ^
      isWhitelistMode.hashCode ^
      excludeOtp.hashCode ^
      excludeFinance.hashCode ^
      excludeHealth.hashCode ^
      excludeSystemServices.hashCode ^
      droppedCount.hashCode;

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

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

  /// Retrieves native ingestion guardrails preferences from the Android side.
  Future<IngestionGuardrails> getIngestionGuardrails() async {
    try {
      final result = await _channel.invokeMethod<Map>('getIngestionGuardrails');
      if (result == null) return const IngestionGuardrails();
      return IngestionGuardrails.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.getIngestionGuardrails failed: ${e.message}');
      return const IngestionGuardrails();
    } on MissingPluginException {
      return const IngestionGuardrails();
    }
  }

  /// Updates native ingestion guardrails preferences on the Android side.
  Future<bool> updateIngestionGuardrails(IngestionGuardrails guardrails) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'updateIngestionGuardrails',
        guardrails.toMap(),
      );
      return result ?? true;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('NotificationBridge.updateIngestionGuardrails failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

