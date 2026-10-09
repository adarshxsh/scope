import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/widgets/model_explainability_widget.dart';
import 'package:scope/widgets/ai_reason_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AttentionDatabase db;

  setUp(() {
    db = AttentionDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Inference Audit Trail & Feature Explainability Tests', () {
    test('InferenceAuditLogDao insert, retrieve, and 30-day auto-purge', () async {
      final now = DateTime.now();
      final old35Days = now.subtract(const Duration(days: 35)).millisecondsSinceEpoch;
      final recent = now.millisecondsSinceEpoch;

      final oldEntry = InferenceAuditLogEntry(
        id: 'audit_old',
        notificationId: 'notif_old',
        timestamp: old35Days,
        rawModelScore: 0.80,
        ruleMatchScore: 0.85,
        fusedScore: 0.82,
        finalScore: 0.82,
        overrideTriggers: null,
        topFeatureAttributions: {'Contains Money': 0.35},
        inputFeatureVector: {'contains_money': 1.0},
        latencyMs: 3,
      );

      final newEntry = InferenceAuditLogEntry(
        id: 'audit_new',
        notificationId: 'notif_new',
        timestamp: recent,
        rawModelScore: 0.95,
        ruleMatchScore: 1.0,
        fusedScore: 0.98,
        finalScore: 0.98,
        overrideTriggers: 'otp_security',
        topFeatureAttributions: {'OTP Code': 0.45},
        inputFeatureVector: {'contains_otp': 1.0},
        latencyMs: 2,
      );

      await db.inferenceAuditLogDao.insertAuditLog(oldEntry);
      await db.inferenceAuditLogDao.insertAuditLog(newEntry);

      expect(await db.inferenceAuditLogDao.getCount(), equals(2));

      final fetchedNew = await db.inferenceAuditLogDao.getAuditLogForNotification('notif_new');
      expect(fetchedNew, isNotNull);
      expect(fetchedNew!.rawModelScore, equals(0.95));
      expect(fetchedNew.overrideTriggers, equals('otp_security'));
      expect(fetchedNew.topFeatureAttributions, containsPair('OTP Code', 0.45));

      // Test 30-day auto-purge via runSetBasedCleanup
      final cutoff = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      await db.runSetBasedCleanup(cutoff);

      expect(await db.inferenceAuditLogDao.getCount(), equals(1));
      final remaining = await db.inferenceAuditLogDao.getAllAuditLogs();
      expect(remaining.first.id, equals('audit_new'));
    });

    test('GhostAnalysisEngine creates and persists complete audit log on analyze()', () async {
      final engine = GhostAnalysisEngine(db: db);
      await engine.initialize();

      final notif = AppNotification(
        id: 'notif_bank_123',
        packageName: 'com.hdfcbank.mobile',
        title: 'Bank Alert',
        content: 'Your account was debited Rs. 2,500 at Amazon.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await engine.analyze(notif);
      expect(result.priority, equals('critical'));

      final auditLog = await engine.getAuditLog('notif_bank_123');
      expect(auditLog, isNotNull);
      expect(auditLog!.notificationId, equals('notif_bank_123'));
      expect(auditLog.rawModelScore, isNotNull);
      expect(auditLog.finalScore, greaterThan(0.0));
      expect(auditLog.latencyMs, isNonNegative);
      expect(auditLog.topFeatureAttributions, isNotNull);
      expect(auditLog.inputFeatureVector, isNotNull);
    });

    test('Feature attribution extraction for OTP and Social package ceiling', () async {
      // 1. Test OTP notification attributions
      final otpNotif = AppNotification(
        id: 'otp_1',
        packageName: 'com.whatsapp',
        title: 'WhatsApp Code',
        content: 'Your verification code is 492810. Valid for 10 minutes.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final engine = GhostAnalysisEngine(db: db);
      await engine.initialize();
      await engine.analyze(otpNotif);

      final otpAudit = await engine.getAuditLog('otp_1');
      expect(otpAudit, isNotNull);
      expect(otpAudit!.topFeatureAttributions, isNotNull);
      expect(otpAudit.topFeatureAttributions, containsPair('OTP / Security Code', 0.45));

      // 2. Test Social package ceiling override attribution
      final socialNotif = AppNotification(
        id: 'social_1',
        packageName: 'com.instagram.android',
        title: 'New Like',
        content: 'John liked your recent photo.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await engine.analyze(socialNotif);
      final socialAudit = await engine.getAuditLog('social_1');
      expect(socialAudit, isNotNull);
      expect(socialAudit!.overrideTriggers, contains('social'));
      expect(socialAudit.topFeatureAttributions, isNotEmpty);
    });

    testWidgets('ModelExplainabilityWidget renders feature attribution bars and score trace', (WidgetTester tester) async {
      final notif = AppNotification(
        id: 'ui_notif_1',
        packageName: 'com.hdfcbank.mobile',
        title: 'Debit Alert',
        content: 'Account debited Rs. 1,500. OTP: 391048.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        priority: 'critical',
        priorityScore: 0.95,
      );

      final auditLog = InferenceAuditLogEntry(
        id: 'audit_ui',
        notificationId: 'ui_notif_1',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        rawModelScore: 0.90,
        ruleMatchScore: 1.0,
        fusedScore: 0.95,
        finalScore: 0.95,
        overrideTriggers: 'otp_security',
        topFeatureAttributions: {
          'OTP / Security Code': 0.45,
          'Payment Amount (₹1500.0)': 0.35,
        },
        inputFeatureVector: {'contains_otp': 1.0},
        latencyMs: 3,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ModelExplainabilityWidget(
                notification: notif,
                auditLog: auditLog,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Model Explainability & Feature Attribution'), findsOneWidget);
      expect(find.text('Top Feature Attribution Weights'), findsOneWidget);
      expect(find.text('OTP / Security Code'), findsOneWidget);
      expect(find.text('+0.45'), findsOneWidget);
      expect(find.text('Score Evolution Trace'), findsOneWidget);
      expect(find.text('Raw Model'), findsOneWidget);
      expect(find.text('Final Score'), findsOneWidget);
    });

    testWidgets('AIReasonWidget renders quantitative attributions and fused score badge', (WidgetTester tester) async {
      final notif = AppNotification(
        id: 'ui_notif_2',
        packageName: 'com.google.android.apps.messaging',
        title: 'Bank Verification',
        content: 'Your OTP code is 918234 for payment of Rs. 500.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        priority: 'high',
        priorityScore: 0.85,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AIReasonWidget(notification: notif),
          ),
        ),
      );

      expect(find.text('Why this matters'), findsOneWidget);
      expect(find.text('Fused Score: 85%'), findsOneWidget);
      expect(find.text('OTP / Security Code'), findsOneWidget);
      expect(find.text('+0.45'), findsOneWidget);
    });
  });
}
