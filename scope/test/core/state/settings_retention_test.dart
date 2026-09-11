import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/state/providers.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AttentionDatabase db;

  setUp(() {
    db = AttentionDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Settings & Dynamic Retention Tests', () {
    test(
      'AppSettingsNotifier initializes defaults and updates settings',
      () async {
        final notifier = AppSettingsNotifier(db);
        expect(notifier.state.retentionDays, equals(7));
        expect(notifier.state.storageQuota, equals(-1));
        expect(notifier.state.telemetryEnabled, isTrue);

        await notifier.setRetentionDays(1);
        expect(notifier.state.retentionDays, equals(1));

        await notifier.setStorageQuota(500);
        expect(notifier.state.storageQuota, equals(500));

        await notifier.setTelemetryEnabled(false);
        expect(notifier.state.telemetryEnabled, isFalse);

        final persisted = await db.appSettingsDao.getSettings();
        expect(persisted.retentionDays, equals(1));
        expect(persisted.storageQuota, equals(500));
        expect(persisted.telemetryEnabled, isFalse);
      },
    );

    test(
      'GhostAnalysisEngine suppresses telemetry trace when telemetryEnabled is false',
      () async {
        final engine = GhostAnalysisEngine(telemetryEnabled: false);

        final rawNotif = AppNotification(
          id: 'n-telemetry-off',
          packageName: 'com.whatsapp',
          title: 'Meeting',
          content: 'See you at 3pm',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final analyzed = await engine.analyze(rawNotif);
        expect(analyzed.explanation, equals('[Telemetry logging disabled]'));
        expect(analyzed.latencyMs, isNull);
      },
    );

    testWidgets(
      'SettingsScreen displays interactive retention and quota tiles',
      (WidgetTester tester) async {
        final container = ProviderContainer();

        final controller = NotificationController(container: container);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(body: SettingsScreen(controller: controller)),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Ghost AI Engine'), findsOneWidget);
        expect(find.text('Telemetry & Privacy'), findsOneWidget);
        expect(find.text('Data Retention Window'), findsOneWidget);
        expect(find.text('Storage Quota Limit'), findsOneWidget);
        expect(find.text('7 Days (Default)'), findsOneWidget);
        expect(find.text('Unlimited (Default)'), findsOneWidget);

        // Tap Data Retention Window tile
        await tester.tap(find.text('Data Retention Window'));
        await tester.pumpAndSettle();

        expect(find.text('24 Hours (1 Day)'), findsOneWidget);
        expect(find.text('30 Days'), findsOneWidget);

        // Select 24 Hours
        await tester.tap(find.text('24 Hours (1 Day)'));
        await tester.pumpAndSettle();

        final settings = container.read(appSettingsProvider);
        expect(settings.retentionDays, equals(1));

        controller.dispose();
        container.dispose();
      },
    );
  });
}
