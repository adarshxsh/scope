import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/hashed_logger.dart';

void main() {
  group('HashedLogger Tests', () {
    test('DJB2 hashing produces deterministic, expected values', () {
      expect(HashedLogger.djb2('com.whatsapp'), equals(3284758266));
      expect(HashedLogger.djb2('Alice'), equals(215236003));
      expect(HashedLogger.djb2('Hello Mom'), equals(1753192290));
      expect(HashedLogger.djb2(''), equals(5381));
    });

    test('DJB2 hash matches AppNotification stable hash generation', () {
      const pkg = 'com.whatsapp';
      const title = 'Alice';
      const content = 'Hello Mom';
      const timestamp = 1625097600000;

      final stableId = AppNotification.generateStableId(
        packageName: pkg,
        timestamp: timestamp,
        title: title,
        content: content,
      );

      final pkgHash = HashedLogger.djb2(pkg);
      final titleHash = HashedLogger.djb2(title);
      final contentHash = HashedLogger.djb2(content);

      expect(stableId, equals('${pkgHash}_${timestamp}_${titleHash}_$contentHash'));
    });

    test('Character count helper returns accurate length', () {
      expect(HashedLogger.charCount('Hello'), equals(5));
      expect(HashedLogger.charCount(''), equals(0));
      expect(HashedLogger.charCount(null), equals(0));
    });

    test('Structured inference report logging executes safely', () {
      const notif = AppNotification(
        id: 'test_1',
        packageName: 'com.whatsapp',
        title: 'Secret Title',
        content: 'Sensitive OTP 123456',
        timestamp: 1000,
        category: 'msg',
        extractedFeatures: {'hasOtp': true, 'contains_otp': true},
      );

      const result = GhostAIResult(
        reviewScore: 0.95,
        inferenceTimeUs: 1500,
        featureVector: [1.0, 2.0, 3.0],
        predictedScore: 0.90,
        ruleScore: 1.0,
      );

      expect(() => HashedLogger.logInferenceReport(notif, result), returnsNormally);
    });

    test('Notification event logging executes safely', () {
      const notif = AppNotification(
        id: 'test_2',
        packageName: 'com.gmail',
        title: 'Bank Statement',
        content: 'Account balance updated',
        timestamp: 2000,
      );

      expect(
        () => HashedLogger.logNotification('TestTag', notif, event: 'Captured'),
        returnsNormally,
      );
    });

    test('Hashing overhead constraint is well under 1 millisecond', () {
      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 1000; i++) {
        HashedLogger.djb2('Sample notification title for performance test $i');
        HashedLogger.djb2('Sample notification content body text for performance test $i');
      }
      stopwatch.stop();

      // 1000 notifications hashed in < 100ms means < 0.1ms per notification (target: <1ms)
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });
  });
}
