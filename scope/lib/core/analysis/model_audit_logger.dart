import 'package:flutter/foundation.dart';
import 'package:scope/core/utils/pii_redactor.dart';

/// Single audit log entry tracking model lifecycle state, verification, and adaptation events.
class ModelAuditEvent {
  final DateTime timestamp;
  final String eventType;
  final String message;
  final Map<String, dynamic>? metadata;

  ModelAuditEvent({
    DateTime? timestamp,
    required this.eventType,
    required String message,
    this.metadata,
  })  : timestamp = timestamp ?? DateTime.now(),
        message = PiiRedactor.redact(message);

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp.toIso8601String(),
        'eventType': eventType,
        'message': message,
        if (metadata != null) 'metadata': metadata,
      };

  @override
  String toString() =>
      '[${timestamp.toIso8601String()}] [$eventType] $message${metadata != null ? ' $metadata' : ''}';
}

/// Audit logger managing structured, PII-sanitized telemetry logs for model lifecycle.
class ModelAuditLogger {
  static final ModelAuditLogger instance = ModelAuditLogger._();

  final List<ModelAuditEvent> _logs = [];
  static const int _maxLogs = 200;

  ModelAuditLogger._();

  /// Logs a structured model lifecycle audit event with PII redaction.
  void log(
    String eventType,
    String message, {
    Map<String, dynamic>? metadata,
  }) {
    final sanitizedMetadata = metadata != null ? _sanitizeMetadata(metadata) : null;
    final event = ModelAuditEvent(
      eventType: eventType,
      message: message,
      metadata: sanitizedMetadata,
    );

    _logs.add(event);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }

    if (kDebugMode) {
      debugPrint('ModelAuditLogger: $event');
    }
  }

  /// Returns unmodifiable list of current audit logs.
  List<ModelAuditEvent> get logs => List.unmodifiable(_logs);

  /// Clears all audit logs.
  void clear() {
    _logs.clear();
  }

  Map<String, dynamic> _sanitizeMetadata(Map<String, dynamic> input) {
    final result = <String, dynamic>{};
    input.forEach((key, value) {
      if (value is String) {
        result[key] = PiiRedactor.redact(value);
      } else {
        result[key] = value;
      }
    });
    return result;
  }
}
