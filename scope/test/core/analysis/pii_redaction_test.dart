import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/analysis/policy_engine.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/state/providers.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/converters.dart';
import 'package:scope/database/drift_notification_storage.dart';
import 'package:scope/screens/diagnostic_screen.dart';
import 'package:scope/screens/ai_playground_screen.dart';

class FakeAnalysisEngine extends GhostAnalysisEngine {
  @override
  Future<void> initialize() async {}

  @override
  Future<AppNotification> analyze(AppNotification notification) async {
    final features = FeatureExtractor.extract(
      title: notification.title,
      content: notification.content,
    );
    return notification.copyWith(
      priority: 'critical',
      priorityScore: 0.99,
      classifiedCategory: 'finance',
      explanation: 'Test analysis',
      latencyMs: 1,
      extractedFeatures: features.toRedactedMap(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Static PII Redaction Unit & Integration Tests', () {
    test('ExtractedFeatures.toRedactedMap produces standard static tokens', () {
      const features = ExtractedFeatures(
        otp: '987654',
        amount: 1250.50,
        hasDeadline: true,
        urls: ['https://secure.bank.com/pay'],
        emails: ['user@example.com'],
        phoneNumbers: ['+1-800-555-0199'],
      );

      final redacted = features.toRedactedMap();

      expect(redacted['otp'], equals('[REDACTED_OTP]'));
      expect(redacted['amount'], equals('[REDACTED_AMOUNT]'));
      expect(redacted['hasDeadline'], isTrue);
      expect(redacted['urls'], equals(['[REDACTED_URL]']));
      expect(redacted['emails'], equals(['[REDACTED_EMAIL]']));
      expect(redacted['phoneNumbers'], equals(['[REDACTED_PHONE]']));
    });

    test('JsonConverter.toSql sanitizes entity fields for database serialization', () {
      const converter = JsonConverter();
      final rawMap = {
        'otp': '123456',
        'amount': 499.99,
        'hasDeadline': false,
        'urls': ['https://test.com'],
        'emails': ['test@scope.dev'],
        'phoneNumbers': ['9998887770'],
      };

      final sqlString = converter.toSql(rawMap);

      expect(sqlString, contains('[REDACTED_OTP]'));
      expect(sqlString, contains('[REDACTED_AMOUNT]'));
      expect(sqlString, contains('[REDACTED_URL]'));
      expect(sqlString, contains('[REDACTED_EMAIL]'));
      expect(sqlString, contains('[REDACTED_PHONE]'));
      expect(sqlString, isNot(contains('123456')));
      expect(sqlString, isNot(contains('499.99')));
      expect(sqlString, isNot(contains('https://test.com')));
      expect(sqlString, isNot(contains('test@scope.dev')));
      expect(sqlString, isNot(contains('9998887770')));
    });

    test('JsonConverter.fromSql safely parses legacy unredacted records without crashing', () {
      const converter = JsonConverter();
      const legacyJson = '{"otp":"888111","amount":100.0,"hasDeadline":true,"urls":["http://legacy.com"],"emails":["legacy@test.com"],"phoneNumbers":["1112223333"]}';

      final map = converter.fromSql(legacyJson);

      expect(map['otp'], equals('[REDACTED_OTP]'));
      expect(map['amount'], equals('[REDACTED_AMOUNT]'));
      expect(map['hasDeadline'], isTrue);
      expect(map['urls'], equals(['[REDACTED_URL]']));
      expect(map['emails'], equals(['[REDACTED_EMAIL]']));
      expect(map['phoneNumbers'], equals(['[REDACTED_PHONE]']));

      expect(() => ExtractedFeatures.fromMap(map), returnsNormally);
      final features = ExtractedFeatures.fromMap(map);
      expect(features.hasDeadline, isTrue);
      expect(features.amount, isNull);
    });

    test('PolicyEngine priority resolution operates accurately on raw in-memory features', () {
      const rawFeatures = ExtractedFeatures(
        otp: '482715',
        amount: 5000.0,
        hasDeadline: true,
      );

      final notif = AppNotification(
        id: 'test_1',
        packageName: 'com.bank.app',
        title: 'Security OTP',
        content: 'Your OTP is 482715 for Rs. 5,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final priority = PolicyEngine.resolvePriority(
        fusedResult: const AnalysisResult(
          category: 'finance',
          score: 0.95,
          engineName: 'test',
          matchedSignals: [],
          latencyMs: 1,
        ),
        features: rawFeatures,
        notification: notif,
      );

      expect(priority, equals('critical'));
    });

    test('DriftNotificationStorage persists redacted JSON payloads to database', () async {
      final db = AttentionDatabase(NativeDatabase.memory());
      final storage = DriftNotificationStorage(db);

      final notif = AppNotification(
        id: 'db_notif_1',
        packageName: 'com.bank.app',
        title: 'Debit Alert',
        content: 'Rs 1000 debited.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        extractedFeatures: const {
          'otp': null,
          'amount': 1000.0,
          'hasDeadline': false,
          'urls': ['https://bank.com'],
          'emails': ['alert@bank.com'],
          'phoneNumbers': ['1800123456'],
        },
      );

      await storage.save(notif);

      final fetched = await storage.getById('db_notif_1');
      expect(fetched, isNotNull);
      expect(fetched!.extractedFeatures!['amount'], equals('[REDACTED_AMOUNT]'));
      expect(fetched.extractedFeatures!['urls'], equals(['[REDACTED_URL]']));
      expect(fetched.extractedFeatures!['emails'], equals(['[REDACTED_EMAIL]']));
      expect(fetched.extractedFeatures!['phoneNumbers'], equals(['[REDACTED_PHONE]']));

      await db.close();
    });

    testWidgets('DiagnosticScreen displays static redaction placeholders for entity fields', (tester) async {
      final engine = FakeAnalysisEngine();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiagnosticScreen(engine: engine),
          ),
        ),
      );

      final contentField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Content Body',
      );
      await tester.enterText(
        contentField,
        'Your OTP is 882715. Amount Rs 1500 debited. Visit https://bank.com or call +1-800-555-0199 or email support@bank.com.',
      );

      final titleField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Title',
      );
      await tester.enterText(titleField, 'Bank Alert');

      final packageField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Package Name',
      );
      await tester.enterText(packageField, 'com.hdfc.bank');

      await tester.tap(find.text('ANALYZE NOTIFICATION'));
      await tester.pumpAndSettle();

      expect(find.textContaining('[REDACTED_OTP]'), findsWidgets);
      expect(find.textContaining('[REDACTED_AMOUNT]'), findsWidgets);
      expect(find.textContaining('[REDACTED_URL]'), findsWidgets);
      expect(find.textContaining('[REDACTED_EMAIL]'), findsWidgets);
      expect(find.textContaining('[REDACTED_PHONE]'), findsWidgets);
    });

    testWidgets('AiPlaygroundScreen renders sanitized entity chips in post-mortem trace', (tester) async {
      final db = AttentionDatabase(NativeDatabase.memory());
      final storage = DriftNotificationStorage(db);
      final container = ProviderContainer();
      final controller = NotificationController(storage: storage, container: container);

      final notif = AppNotification(
        id: 'pm_1',
        packageName: 'com.whatsapp',
        title: 'Verification',
        content: 'Your code is 654321.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        extractedFeatures: const {
          'otp': '654321',
          'amount': 250.0,
          'hasDeadline': false,
          'urls': ['https://whatsapp.com'],
          'emails': ['verify@whatsapp.com'],
          'phoneNumbers': ['+1234567890'],
        },
      );

      container.read(reviewQueueProvider.notifier).add(notif);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AiPlaygroundScreen(controller: controller),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final notifCard = find.text('Verification');
      expect(notifCard, findsOneWidget);
      await tester.tap(notifCard);
      await tester.pumpAndSettle();

      expect(find.text('OTP:[REDACTED_OTP]'), findsOneWidget);
      expect(find.text('Amount:[REDACTED_AMOUNT]'), findsOneWidget);
      expect(find.text('URL:[REDACTED_URL]'), findsOneWidget);
      expect(find.text('Email:[REDACTED_EMAIL]'), findsOneWidget);
      expect(find.text('Phone:[REDACTED_PHONE]'), findsOneWidget);

      controller.dispose();
      container.dispose();
      await db.close();
    });
  });
}
