import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/model_adaptation_strategy.dart';
import 'package:scope/core/analysis/model_audit_logger.dart';
import 'package:scope/core/analysis/model_verifier.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/pii_redactor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PiiRedactor Tests', () {
    test('redacts OTP passcodes, emails, phone numbers, URLs, credit cards, and auth tokens', () {
      final input =
          'User OTP is 882715 for email john.doe@example.com, phone +1-555-0199, card 4111-1111-1111-1111, visit https://secure.com with bearer token abcdef1234567890xyz.';

      final redacted = PiiRedactor.redact(input);

      expect(redacted.contains('882715'), isFalse);
      expect(redacted.contains('[REDACTED_OTP]'), isTrue);

      expect(redacted.contains('john.doe@example.com'), isFalse);
      expect(redacted.contains('[REDACTED_EMAIL]'), isTrue);

      expect(redacted.contains('+1-555-0199'), isFalse);
      expect(redacted.contains('[REDACTED_PHONE]'), isTrue);

      expect(redacted.contains('4111-1111-1111-1111'), isFalse);
      expect(redacted.contains('[REDACTED_CARD]'), isTrue);

      expect(redacted.contains('https://secure.com'), isFalse);
      expect(redacted.contains('[REDACTED_URL]'), isTrue);

      expect(redacted.contains('abcdef1234567890xyz'), isFalse);
      expect(redacted.contains('[REDACTED_TOKEN]'), isTrue);
    });
  });

  group('ModelVerifier Tests', () {
    test('throws exception when model binary is empty or less than 8 bytes', () {
      expect(
        () => ModelVerifier.verifyBytes(Uint8List(0)),
        throwsA(isA<ModelVerificationException>()),
      );

      expect(
        () => ModelVerifier.verifyBytes(Uint8List(5)),
        throwsA(isA<ModelVerificationException>()),
      );
    });

    test('throws exception when TFL3 FlatBuffer header is missing', () {
      final invalidBytes = Uint8List(20)..fillRange(0, 20, 0);
      expect(
        () => ModelVerifier.verifyBytes(invalidBytes),
        throwsA(isA<ModelVerificationException>()),
      );
    });

    test('throws exception when SHA-256 digest mismatches expected value', () {
      final mockTfliteBytes = Uint8List.fromList([
        0, 0, 0, 0, 84, 70, 76, 51, // offset 4..7: 'T', 'F', 'L', '3'
        0, 0, 0, 0, 0, 0, 0, 0,
      ]);

      expect(
        () => ModelVerifier.verifyBytes(
          mockTfliteBytes,
          expectedSha256: '0000000000000000000000000000000000000000000000000000000000000000',
        ),
        throwsA(isA<ModelVerificationException>()),
      );
    });

    test('verifies valid TFLite header and matching SHA-256 digest', () {
      final mockTfliteBytes = Uint8List.fromList([
        0, 0, 0, 0, 84, 70, 76, 51,
        1, 2, 3, 4, 5, 6, 7, 8,
      ]);

      final digest = ModelVerifier.verifyBytes(mockTfliteBytes);
      expect(digest, isNotEmpty);

      final verifiedDigest = ModelVerifier.verifyBytes(
        mockTfliteBytes,
        expectedSha256: digest,
      );
      expect(verifiedDigest, equals(digest));
    });
  });

  group('ModelAuditLogger Tests', () {
    test('logs audit events with PII sanitization and metadata', () {
      ModelAuditLogger.instance.clear();

      ModelAuditLogger.instance.log(
        'TEST_EVENT',
        'Verification for OTP 123456 user email test@domain.com',
        metadata: {'user': 'user@domain.com', 'count': 42},
      );

      expect(ModelAuditLogger.instance.logs.length, equals(1));
      final log = ModelAuditLogger.instance.logs.first;

      expect(log.eventType, equals('TEST_EVENT'));
      expect(log.message.contains('123456'), isFalse);
      expect(log.message.contains('[REDACTED_OTP]'), isTrue);
      expect(log.message.contains('[REDACTED_EMAIL]'), isTrue);
      expect(log.metadata?['user'], equals('[REDACTED_EMAIL]'));
      expect(log.metadata?['count'], equals(42));
    });
  });

  group('ModelAdaptationStrategy Tests', () {
    test('records user feedback and adapts calibration score offset', () {
      final strategy = ModelAdaptationStrategy(driftThreshold: 0.25);
      strategy.reset();

      expect(strategy.scoreOffset, equals(0.0));
      expect(strategy.disagreementRate, equals(0.0));

      // Record 10 rejected feedback events
      for (int i = 0; i < 10; i++) {
        strategy.recordFeedback(
          UserFeedbackEvent(
            notificationId: 'notif_$i',
            predictedCategory: 'sys',
            predictedScore: 0.85,
            userAction: 'rejected',
          ),
        );
      }

      expect(strategy.scoreOffset, lessThan(0.0));
      expect(strategy.disagreementRate, equals(1.0));
      expect(strategy.isDriftDetected, isTrue);

      final adaptedScore = strategy.applyAdaptation(0.80);
      expect(adaptedScore, lessThan(0.80));

      strategy.reset();
      expect(strategy.scoreOffset, equals(0.0));
      expect(strategy.isDriftDetected, isFalse);
    });
  });

  group('FeatureVector padOrTruncate Tests', () {
    test('pads feature vector when target dimension is larger', () {
      final rawVector = List<double>.generate(63, (i) => i.toDouble());
      final fv = FeatureVector(rawVector);

      final padded = fv.padOrTruncate(64);
      expect(padded.length, equals(64));
      expect(padded.sublist(0, 63), equals(rawVector));
      expect(padded[63], equals(0.0));
    });

    test('truncates feature vector when target dimension is smaller', () {
      final rawVector = List<double>.generate(63, (i) => i.toDouble());
      final fv = FeatureVector(rawVector);

      final truncated = fv.padOrTruncate(30);
      expect(truncated.length, equals(30));
      expect(truncated, equals(rawVector.sublist(0, 30)));
    });
  });

  group('ModelManager & GhostAI Lifecycle Integration Tests', () {
    test('GhostAI prediction uses referenceTimestamp to evaluate historical notifications correctly', () async {
      final notifTimestamp = DateTime.now().millisecondsSinceEpoch - 600000; // 10 mins ago

      final notif = AppNotification(
        id: 'test_hist_1',
        packageName: 'com.whatsapp',
        title: 'WhatsApp Code',
        content: 'Your verification code is 882715. Valid for 10 minutes.',
        timestamp: notifTimestamp,
      );

      // Evaluating with referenceTimestamp equal to creation time -> fresh OTP (score > 0.0)
      final freshResult = await GhostAI.predict(
        notif,
        referenceTimestamp: notifTimestamp,
      );
      expect(freshResult.reviewScore, greaterThan(0.0));

      // Evaluating with referenceTimestamp 15 mins later -> expired OTP (score == 0.0)
      final expiredResult = await GhostAI.predict(
        notif,
        referenceTimestamp: notifTimestamp + 900000,
      );
      expect(expiredResult.reviewScore, equals(0.0));
    });

    test('hotReloadModelFromBytes rejects corrupted model without crashing application', () async {
      final corruptBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      expect(
        () async => await GhostAI.instance.hotReloadModelFromBytes(corruptBytes),
        throwsA(isA<ModelVerificationException>()),
      );

      // Confirm system remains stable and prediction works via fallback
      final notif = AppNotification(
        id: 'test_fallback_1',
        packageName: 'com.example.app',
        title: 'Regular Alert',
        content: 'Meeting starts soon',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(notif);
      expect(result.reviewScore, isA<double>());
    });
  });
}
