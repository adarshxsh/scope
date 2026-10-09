import 'package:flutter_test/flutter_test.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  late AttentionDatabase db;

  setUp(() {
    db = AttentionDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  group('InferenceTelemetryDao Unit Tests', () {
    test('insertTelemetry quantizes timestamp and persists record correctly', () async {
      final unquantizedTs = DateTime(2026, 9, 17, 14, 27, 33).millisecondsSinceEpoch;

      final entry = InferenceTelemetryEntry(
        id: 0,
        notificationId: 'notif-123',
        quantizedTimestamp: unquantizedTs,
        latencyMs: 15,
        modelVersion: '1.0.0-tflite',
        ruleVersion: '2026.06.01',
        engineVersion: '2.0.0-hybrid',
        isFallback: false,
        priorityScore: 0.85,
        priorityLevel: 'high',
        createdAt: DateTime.now(),
      );

      await db.inferenceTelemetryDao.insertTelemetry(entry);

      final list = await db.inferenceTelemetryDao.getAllTelemetry();
      expect(list.length, equals(1));
      expect(list.first.notificationId, equals('notif-123'));
      expect(list.first.latencyMs, equals(15));
      expect(list.first.priorityLevel, equals('high'));

      // Check quantized timestamp (minute 27 -> rounded to minute 15)
      final expectedTs = DateTime(2026, 9, 17, 14, 15, 0).millisecondsSinceEpoch;
      expect(list.first.quantizedTimestamp, equals(expectedTs));
    });

    test('insertAuditLog redacts cleartext PII before persistence', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      const rawMessage = r'User received OTP 998877 for email alice@scope.app with payment $250.00';

      await db.inferenceTelemetryDao.insertAuditLog(
        timestamp: now,
        eventType: 'MODEL_INFERENCE_LOG',
        logMessage: rawMessage,
      );

      final logs = await db.inferenceTelemetryDao.getAllAuditLogs();
      expect(logs.length, equals(1));
      expect(logs.first.eventType, equals('MODEL_INFERENCE_LOG'));

      final storedMsg = logs.first.logMessage;
      expect(storedMsg, contains('[REDACTED_OTP]'));
      expect(storedMsg, contains('[REDACTED_EMAIL]'));
      expect(storedMsg, contains('[REDACTED_AMOUNT]'));
      expect(storedMsg, isNot(contains('998877')));
      expect(storedMsg, isNot(contains('alice@scope.app')));
      expect(storedMsg, isNot(contains(r'$250.00')));
    });


    test('updatePrivacyBudget and getPrivacyBudget manage budget entries', () async {
      final entry = PrivacyBudgetEntry(
        id: 0,
        entity: 'model_retraining',
        allocatedEpsilon: 2.0,
        consumedEpsilon: 0.5,
        delta: 1e-5,
        lastUpdated: DateTime.now(),
      );

      await db.inferenceTelemetryDao.updatePrivacyBudget(entry);

      final fetched = await db.inferenceTelemetryDao.getPrivacyBudget('model_retraining');
      expect(fetched, isNotNull);
      expect(fetched!.allocatedEpsilon, equals(2.0));
      expect(fetched.consumedEpsilon, equals(0.5));
    });

    test('clearAll wipes telemetry, audit, budget, and ledger tables', () async {
      await db.inferenceTelemetryDao.insertTelemetry(InferenceTelemetryEntry(
        id: 0,
        quantizedTimestamp: 1000,
        latencyMs: 10,
        isFallback: false,
        priorityScore: 0.5,
        createdAt: DateTime.now(),
      ));

      await db.inferenceTelemetryDao.insertAuditLog(
        timestamp: 1000,
        eventType: 'TEST_EVENT',
        logMessage: 'Test event message',
      );

      var telemetry = await db.inferenceTelemetryDao.getAllTelemetry();
      var logs = await db.inferenceTelemetryDao.getAllAuditLogs();
      expect(telemetry.length, equals(1));
      expect(logs.length, equals(1));

      await db.inferenceTelemetryDao.clearAll();

      telemetry = await db.inferenceTelemetryDao.getAllTelemetry();
      logs = await db.inferenceTelemetryDao.getAllAuditLogs();
      expect(telemetry, isEmpty);
      expect(logs, isEmpty);
    });
  });
}
