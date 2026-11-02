import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AttentionDatabase db;
  late GhostAnalysisEngine engine;

  setUp(() {
    db = AttentionDatabase.inMemory();
    engine = GhostAnalysisEngine(telemetryDao: db.inferenceTelemetryDao);
  });

  tearDown(() async {
    await db.close();
  });

  group('GhostAnalysisEngine Telemetry Integration Tests', () {
    test('analyze logs anonymized telemetry record on execution', () async {
      final notif = AppNotification(
        id: 'notif-telemetry-001',
        packageName: 'com.bank.app',
        title: r'Account Alert: $500.00 withdrawn',
        content: r'Your account 123456 had a debit of $500.00 at ATM.',
        timestamp: DateTime(2026, 9, 17, 11, 42, 0).millisecondsSinceEpoch,
      );


      final analyzed = await engine.analyze(notif);
      expect(analyzed, isNotNull);
      expect(analyzed.priorityScore, isNotNull);

      final telemetryList = await db.inferenceTelemetryDao.getAllTelemetry();
      expect(telemetryList.length, equals(1));

      final entry = telemetryList.first;
      expect(entry.notificationId, equals('notif-telemetry-001'));
      expect(entry.priorityLevel, equals(analyzed.priority));
      
      // Verify quantized timestamp (minute 42 -> rounded to minute 30)
      final expectedTs = DateTime(2026, 9, 17, 11, 30, 0).millisecondsSinceEpoch;
      expect(entry.quantizedTimestamp, equals(expectedTs));
    });
  });
}
