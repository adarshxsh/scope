import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/analysis/feature_attribution.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  group('FeatureAttributionCalculator Tests', () {
    test('computes attributions for OTP notification', () {
      const notif = AppNotification(
        id: '1',
        packageName: 'com.whatsapp',
        title: 'Verification Code',
        content: 'Your verification code is 882715. Valid for 10 minutes.',
        timestamp: 10000,
      );

      const features = ExtractedFeatures(
        otp: '882715',
        hasDeadline: true,
      );

      final attributions = FeatureAttributionCalculator.computeAttributions(
        notification: notif,
        features: features,
        predictedScore: 1.0,
      );

      expect(attributions, isNotEmpty);
      expect(attributions.any((a) => a.featureKey == 'contains_otp'), isTrue);
      expect(attributions.firstWhere((a) => a.featureKey == 'contains_otp').influence, greaterThan(0.5));
    });

    test('computes attributions for financial transaction notification', () {
      const notif = AppNotification(
        id: '2',
        packageName: 'com.example.bank',
        title: 'Account Debited',
        content: 'Rs. 2500 debited from account xx1234.',
        timestamp: 10000,
      );

      const features = ExtractedFeatures(
        amount: 2500.0,
      );

      final attributions = FeatureAttributionCalculator.computeAttributions(
        notification: notif,
        features: features,
        predictedScore: 0.85,
      );

      expect(attributions, isNotEmpty);
      expect(attributions.any((a) => a.featureKey == 'contains_amount'), isTrue);
      expect(attributions.firstWhere((a) => a.featureKey == 'contains_amount').description, contains('₹2500'));
    });

    test('computes attributions for promotional notification', () {
      const notif = AppNotification(
        id: '3',
        packageName: 'com.shopping.app',
        title: '50% OFF Sale',
        content: 'Buy today and get 50% discount on shoes!',
        timestamp: 10000,
      );

      const features = ExtractedFeatures();

      final attributions = FeatureAttributionCalculator.computeAttributions(
        notification: notif,
        features: features,
        predictedScore: 0.05,
      );

      expect(attributions.any((a) => a.featureKey == 'promo_keywords'), isTrue);
      expect(attributions.firstWhere((a) => a.featureKey == 'promo_keywords').influence, lessThan(0.0));
    });

    test('sanitizeText redacts sensitive OTP codes, emails, and phone numbers', () {
      const input = 'Use code 883102 sent to user@example.com or +1 555-123-4567';
      final sanitized = FeatureAttributionCalculator.sanitizeText(input);

      expect(sanitized, isNot(contains('883102')));
      expect(sanitized, isNot(contains('user@example.com')));
      expect(sanitized, contains('[REDACTED_CODE]'));
      expect(sanitized, contains('[REDACTED_EMAIL]'));
      expect(sanitized, contains('[REDACTED_PHONE]'));
    });
  });
}
