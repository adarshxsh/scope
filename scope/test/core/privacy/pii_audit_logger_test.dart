import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/privacy/pii_audit_logger.dart';

void main() {
  setUp(() {
    PiiAuditLogger.clear();
  });

  group('PiiAuditLogger Unit Tests', () {
    test('logs PII redaction events without storing sensitive values', () {
      final event = PiiAuditLogger.logRedaction(
        notificationId: 'notif_100',
        piiTypes: [PiiType.otp, PiiType.phone],
        action: 'STORAGE_PERSISTENCE',
      );

      expect(event.notificationId, equals('notif_100'));
      expect(event.piiTypes, contains(PiiType.otp));
      expect(event.piiTypes, contains(PiiType.phone));
      expect(event.action, equals('STORAGE_PERSISTENCE'));
      expect(event.success, isTrue);
      expect(event.fallbackApplied, isFalse);

      final events = PiiAuditLogger.getEvents();
      expect(events.length, equals(1));
    });

    test('enforces ring buffer memory capacity limit (200 entries)', () {
      for (int i = 0; i < 250; i++) {
        PiiAuditLogger.logRedaction(
          notificationId: 'notif_$i',
          piiTypes: [PiiType.otp],
          action: 'TEST_ACTION',
        );
      }

      final events = PiiAuditLogger.getEvents();
      expect(events.length, equals(PiiAuditLogger.maxCapacity));
      expect(events.first.notificationId, equals('notif_50'));
      expect(events.last.notificationId, equals('notif_249'));
    });

    test('logs fallback error recovery events', () {
      final event = PiiAuditLogger.logFallback(
        notificationId: 'err_notif',
        action: 'TEST_FALLBACK',
        errorMessage: 'Simulated parsing failure',
      );

      expect(event.fallbackApplied, isTrue);
      expect(event.success, isFalse);
      expect(event.details, contains('Simulated parsing failure'));
    });

    test('returns accurate statistics', () {
      PiiAuditLogger.logRedaction(
        notificationId: 'n1',
        piiTypes: [PiiType.otp, PiiType.email],
        action: 'A1',
      );
      PiiAuditLogger.logRedaction(
        notificationId: 'n2',
        piiTypes: [PiiType.otp, PiiType.phone],
        action: 'A2',
      );

      final stats = PiiAuditLogger.getStats();
      expect(stats['totalEvents'], equals(2));
      final typeCounts = stats['typeCounts'] as Map<String, dynamic>;
      expect(typeCounts['otp'], equals(2));
      expect(typeCounts['email'], equals(1));
      expect(typeCounts['phone'], equals(1));
    });
  });
}
