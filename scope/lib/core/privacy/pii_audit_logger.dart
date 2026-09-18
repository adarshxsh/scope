import 'package:flutter/foundation.dart';

/// Types of PII detected and redacted.
enum PiiType {
  otp('OTP / Verification Code'),
  phone('Phone Number'),
  email('Email Address'),
  card('Credit/Debit Card Number'),
  credential('Password / Passcode / Secret'),
  accountNumber('Account / Reference ID');

  final String label;
  const PiiType(this.label);
}

/// Audit event representing a PII redaction action.
class PiiAuditEvent {
  final String id;
  final DateTime timestamp;
  final String notificationId;
  final List<PiiType> piiTypes;
  final String action;
  final bool success;
  final bool fallbackApplied;
  final String details;

  PiiAuditEvent({
    required this.id,
    required this.timestamp,
    required this.notificationId,
    required this.piiTypes,
    required this.action,
    this.success = true,
    this.fallbackApplied = false,
    this.details = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'notificationId': notificationId,
      'piiTypes': piiTypes.map((t) => t.name).toList(),
      'action': action,
      'success': success,
      'fallbackApplied': fallbackApplied,
      'details': details,
    };
  }

  @override
  String toString() {
    return 'PiiAuditEvent(id: $id, time: $timestamp, notificationId: $notificationId, '
        'types: ${piiTypes.map((t) => t.name).toList()}, action: $action, '
        'success: $success, fallback: $fallbackApplied)';
  }
}

/// Audit logger for PII detection and redaction events.
///
/// Features:
/// - Enforces memory safety using a bounded ring buffer (max 200 events).
/// - NEVER logs raw sensitive PII content strings.
/// - Operates fully on-device without network calls.
class PiiAuditLogger {
  static const int maxCapacity = 200;
  static final List<PiiAuditEvent> _events = [];
  static int _idCounter = 0;

  /// Records a PII redaction event in the audit log.
  static PiiAuditEvent logRedaction({
    required String notificationId,
    required List<PiiType> piiTypes,
    required String action,
    bool success = true,
    bool fallbackApplied = false,
    String details = '',
  }) {
    _idCounter++;
    final event = PiiAuditEvent(
      id: 'audit_$_idCounter',
      timestamp: DateTime.now(),
      notificationId: notificationId.isNotEmpty ? notificationId : 'unknown',
      piiTypes: List.unmodifiable(piiTypes),
      action: action,
      success: success,
      fallbackApplied: fallbackApplied,
      details: details,
    );

    _events.add(event);
    if (_events.length > maxCapacity) {
      _events.removeAt(0); // Maintain bounded memory overhead
    }

    if (kDebugMode) {
      debugPrint('[PII Audit] ${event.action} for ${event.notificationId}: ${event.piiTypes.map((e) => e.name).toList()} (Fallback: ${event.fallbackApplied})');
    }

    return event;
  }

  /// Records a fallback recovery event when redaction encounters an exception.
  static PiiAuditEvent logFallback({
    required String notificationId,
    required String action,
    required String errorMessage,
  }) {
    return logRedaction(
      notificationId: notificationId,
      piiTypes: PiiType.values,
      action: action,
      success: false,
      fallbackApplied: true,
      details: 'Fallback recovery applied: $errorMessage',
    );
  }

  /// Returns an unmodifiable copy of all recorded audit events.
  static List<PiiAuditEvent> getEvents() {
    return List.unmodifiable(_events);
  }

  /// Returns aggregated statistics of redacted PII categories.
  static Map<String, dynamic> getStats() {
    final counts = <String, int>{
      for (final type in PiiType.values) type.name: 0,
    };
    int fallbacks = 0;

    for (final event in _events) {
      if (event.fallbackApplied) fallbacks++;
      for (final type in event.piiTypes) {
        counts[type.name] = (counts[type.name] ?? 0) + 1;
      }
    }

    return {
      'totalEvents': _events.length,
      'fallbackCount': fallbacks,
      'typeCounts': counts,
    };
  }

  /// Clears recorded audit logs (primarily for testing or reset).
  static void clear() {
    _events.clear();
    _idCounter = 0;
  }
}
