import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/analysis/metadata_analyzer.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  group('FeatureExtractor', () {
    test('extracts OTP successfully when context is present', () {
      final features = FeatureExtractor.extract(
        title: 'Security Alert',
        content: 'Your HDFC OTP is 482715. Do not share it with anyone.',
      );
      expect(features.otp, equals('482715'));
    });

    test('ignores year digits in OTP check', () {
      final features = FeatureExtractor.extract(
        title: 'Update Year 2026',
        content: 'This code is not an OTP.',
      );
      expect(features.otp, isNull);
    });

    test('extracts transaction amounts correctly', () {
      final features = FeatureExtractor.extract(
        title: 'HDFC Bank debit alert',
        content: 'Rs. 15,000 debited from A/c XX4523 on 26-Jun-2026.',
      );
      expect(features.amount, equals(15000.0));
    });

    test('extracts decimal transaction amounts correctly', () {
      final features = FeatureExtractor.extract(
        title: 'Payment confirmation',
        content: 'You spent \$125.75 at Starbux.',
      );
      expect(features.amount, equals(125.75));
    });

    test('identifies deadlines', () {
      final features = FeatureExtractor.extract(
        title: 'Deadline warning',
        content: 'Your scholarship application closes tomorrow! Apply now.',
      );
      expect(features.hasDeadline, isTrue);
    });

    test('extracts URLs, emails, and phone numbers', () {
      final features = FeatureExtractor.extract(
        title: 'Support request',
        content: 'Visit https://help.scope.dev or email support@scope.dev or call 1800-452-9871.',
      );
      expect(features.urls, contains('https://help.scope.dev'));
      expect(features.emails, contains('support@scope.dev'));
      expect(features.phoneNumbers, contains('1800-452-9871'));
    });
  });

  group('MetadataAnalyzer', () {
    test('maps packages to category hints', () {
      final notif = AppNotification(
        id: '1',
        packageName: 'com.whatsapp',
        title: 'Mom',
        content: 'Where are you?',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      expect(MetadataAnalyzer.getCategoryHint(notif), equals('msg'));
    });

    test('flags system ongoing notifications', () {
      final notifOngoing = AppNotification(
        id: '2',
        packageName: 'android',
        title: 'Downloading...',
        content: 'System update in progress',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isOngoing: true,
      );
      expect(MetadataAnalyzer.isSystemOngoing(notifOngoing), isTrue);

      final notifNotOngoing = notifOngoing.copyWith(isOngoing: false);
      expect(MetadataAnalyzer.isSystemOngoing(notifNotOngoing), isFalse);
    });
  });
}
