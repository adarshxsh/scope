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
        content:
            'Visit https://help.scope.dev or email support@scope.dev or call 1800-452-9871.',
      );
      expect(features.urls, contains('https://help.scope.dev'));
      expect(features.emails, contains('support@scope.dev'));
      expect(features.phoneNumbers, contains('1800-452-9871'));
    });

    test('extracts a fixed-size numerical vector for TFLite', () {
      final input = NotificationFeatureInput(
        appName: 'Scope Bank',
        packageName: 'com.scope.bank',
        title: 'Security OTP',
        body:
            'OTP 482715 for ₹1,250 paid at Amazon. Join https://meet.google.com/abc-defg-hij by tomorrow! Order #ABCD1234. coupon SAVE20 gives 20% off.',
        timestampMillis: DateTime.utc(2026, 6, 26, 10).millisecondsSinceEpoch,
        android: const AndroidNotificationMetadata(
          importance: 4,
          conversation: true,
          visibility: 1,
          ongoing: false,
          foregroundService: false,
          notificationCategory: 'msg',
          channelId: 'payments',
          channelName: 'Payment alerts',
          containsAttachment: true,
        ),
      );

      final vector = FeatureExtractor.extractVector(input);
      final named = vector.toNamedMap();

      expect(FeatureVector.featureNames, hasLength(FeatureVector.size));
      expect(vector.values, hasLength(FeatureVector.size));
      expect(vector.values.every((value) => value.isFinite), isTrue);
      expect(named['contains_otp'], equals(1.0));
      expect(named['contains_money'], equals(1.0));
      expect(named['contains_currency_symbol'], equals(1.0));
      expect(named['contains_meeting_link'], equals(1.0));
      expect(named['contains_attachment'], equals(1.0));
      expect(named['contains_deadline'], equals(1.0));
      expect(named['deadline_minutes_remaining'], equals(1440.0));
      expect(named['amount'], equals(1250.0));
      expect(named['currency'], equals(1.0));
      expect(named['otp_length'], equals(6.0));
      expect(named['importance'], equals(4.0));
      expect(named['conversation'], equals(1.0));
      expect(named['notification_category'], equals(6.0));
      expect(named['timestamp_hour'], equals(10.0));
      expect(named['day_of_week'], equals(5.0));
    });

    test('vector extraction is deterministic', () {
      final input = NotificationFeatureInput(
        appName: 'Calendar',
        packageName: 'com.google.android.calendar',
        title: 'Project review',
        body: 'Reminder: project review meeting in 30 minutes on Zoom.',
        timestampMillis: DateTime.utc(
          2026,
          6,
          26,
          8,
          15,
        ).millisecondsSinceEpoch,
        android: AndroidNotificationMetadata.fromMap({
          'importance': 3,
          'category': 'event',
          'channelId': 'calendar-default',
          'channelName': 'Calendar reminders',
        }),
      );

      final first = FeatureExtractor.extractVector(input).toList();
      final second = FeatureExtractor.extractVector(input).toList();

      expect(first, equals(second));
      expect(
        first[FeatureVector.featureNames.indexOf('deadline_minutes_remaining')],
        equals(30.0),
      );
    });

    test('converts AppNotification directly to a vector list', () {
      final notification = AppNotification(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Mom',
        content: 'Where are you?',
        timestamp: DateTime.utc(2026, 6, 26, 9).millisecondsSinceEpoch,
        category: 'msg',
      );

      final values = FeatureExtractor.extractFromAppNotification(notification);

      expect(values, isA<List<double>>());
      expect(values, hasLength(FeatureVector.size));
      expect(
        values[FeatureVector.featureNames.indexOf('contains_question')],
        1.0,
      );
      expect(values[FeatureVector.featureNames.indexOf('person_present')], 1.0);
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
