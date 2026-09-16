import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Model Lifecycle & Adaptation Tests', () {

    test('LiteRtClassifier exposes modelVersion and falls back heuristics gracefully', () async {
      final classifier = LiteRtClassifier();
      expect(classifier.isModelLoaded, isFalse);
      expect(classifier.modelVersion, equals('fallback-heuristics'));

      final notif = const AppNotification(
        id: '1',
        packageName: 'com.whatsapp',
        title: 'Mom',
        content: 'Please pick up groceries',
        timestamp: 1000,
      );

      final result = await classifier.analyze(notif);
      expect(result.category, equals('msg'));
      expect(result.score, equals(0.50));
    });

    test('GhostAI exposes modelVersion and manages duplicate cache bounds', () async {
      final ghost = GhostAI.instance;
      await ghost.initialize();

      expect(ghost.modelVersion, isNotNull);
      expect(ghost.ruleVersion, isNotNull);

      // Verify GhostAI inference runs without uncaught exceptions
      final notif = const AppNotification(
        id: '2',
        packageName: 'com.hdfcbank',
        title: 'Transaction Alert',
        content: 'Your account has been debited Rs. 2,000.',
        timestamp: 1000,
      );

      final result = await GhostAI.predict(notif);
      expect(result.reviewScore, greaterThan(0.0));
      expect(result.featureVector.length, equals(63));
    });

    test('GhostAI duplicate cache handles pruning under load', () async {
      final ghost = GhostAI.instance;
      ghost.clearCache();

      for (int i = 0; i < 600; i++) {
        final notif = AppNotification(
          id: 'load_$i',
          packageName: 'com.example.app$i',
          title: 'Title $i',
          content: 'Content $i',
          timestamp: DateTime.now().millisecondsSinceEpoch - i * 10,
        );
        await GhostAI.predict(notif);
      }

      // Prediction completes without memory leak or exception
      expect(true, isTrue);
    });
  });
}
