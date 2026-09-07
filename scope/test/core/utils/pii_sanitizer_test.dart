import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/providers.dart';
import 'package:scope/core/utils/pii_sanitizer.dart';
import 'package:scope/database/converters.dart';

void main() {
  group('PiiSanitizer Unit Tests', () {
    test('sanitizes cleartext feature maps into static redaction masks', () {
      final rawMap = {
        'otp': '883102',
        'amount': 5000.0,
        'hasDeadline': true,
        'urls': ['https://example.com/verify?token=abc'],
        'emails': ['user@example.com'],
        'phoneNumbers': ['+1234567890'],
        'deadline_minutes_remaining': 15,
      };

      final sanitized = PiiSanitizer.sanitizeFeatureMap(rawMap);

      expect(sanitized['otp'], equals(PiiRedactionMasks.otp));
      expect(sanitized['amount'], equals(PiiRedactionMasks.amount));
      expect(sanitized['hasDeadline'], isTrue);
      expect(sanitized['urls'], equals([PiiRedactionMasks.url]));
      expect(sanitized['emails'], equals([PiiRedactionMasks.email]));
      expect(sanitized['phoneNumbers'], equals([PiiRedactionMasks.phoneNumber]));
      expect(sanitized['deadline_minutes_remaining'], equals(15));
    });

    test('is idempotent when called on already sanitized feature maps', () {
      final sanitizedOnce = {
        'otp': PiiRedactionMasks.otp,
        'amount': PiiRedactionMasks.amount,
        'hasDeadline': true,
        'urls': [PiiRedactionMasks.url],
        'emails': [PiiRedactionMasks.email],
        'phoneNumbers': [PiiRedactionMasks.phoneNumber],
      };

      final sanitizedTwice = PiiSanitizer.sanitizeFeatureMap(sanitizedOnce);

      expect(sanitizedTwice['otp'], equals(PiiRedactionMasks.otp));
      expect(sanitizedTwice['amount'], equals(PiiRedactionMasks.amount));
      expect(sanitizedTwice['hasDeadline'], isTrue);
      expect(sanitizedTwice['urls'], equals([PiiRedactionMasks.url]));
      expect(sanitizedTwice['emails'], equals([PiiRedactionMasks.email]));
      expect(sanitizedTwice['phoneNumbers'], equals([PiiRedactionMasks.phoneNumber]));
    });

    test('ExtractedFeatures.toSanitizedMap returns masked feature map', () {
      const features = ExtractedFeatures(
        otp: '123456',
        amount: 799.50,
        hasDeadline: true,
        urls: ['http://test.com'],
        emails: ['test@domain.com'],
        phoneNumbers: ['9876543210'],
      );

      final sanitized = features.toSanitizedMap();

      expect(sanitized['otp'], equals(PiiRedactionMasks.otp));
      expect(sanitized['amount'], equals(PiiRedactionMasks.amount));
      expect(sanitized['hasDeadline'], isTrue);
      expect(sanitized['urls'], equals([PiiRedactionMasks.url]));
      expect(sanitized['emails'], equals([PiiRedactionMasks.email]));
      expect(sanitized['phoneNumbers'], equals([PiiRedactionMasks.phoneNumber]));
    });

    test('ExtractedFeatures.fromMap correctly parses sanitized feature map', () {
      final sanitizedMap = {
        'otp': PiiRedactionMasks.otp,
        'amount': PiiRedactionMasks.amount,
        'hasDeadline': true,
        'urls': [PiiRedactionMasks.url],
        'emails': [PiiRedactionMasks.email],
        'phoneNumbers': [PiiRedactionMasks.phoneNumber],
      };

      final features = ExtractedFeatures.fromMap(sanitizedMap);

      expect(features.otp, equals(PiiRedactionMasks.otp));
      expect(features.hasAmount, isTrue);
      expect(features.amountDisplay, equals(PiiRedactionMasks.amount));
      expect(features.hasDeadline, isTrue);
      expect(features.urls, equals([PiiRedactionMasks.url]));
      expect(features.emails, equals([PiiRedactionMasks.email]));
      expect(features.phoneNumbers, equals([PiiRedactionMasks.phoneNumber]));
    });

    test('JsonConverter.toSql enforces feature map sanitization for database persistence', () {
      const converter = JsonConverter();
      final rawMap = {
        'otp': '998877',
        'amount': 1250.0,
        'hasDeadline': true,
        'urls': ['https://secret.bank.com'],
        'emails': ['secret@bank.com'],
        'phoneNumbers': ['1800123456'],
      };

      final sqlJson = converter.toSql(rawMap);

      expect(sqlJson, contains(PiiRedactionMasks.otp));
      expect(sqlJson, contains(PiiRedactionMasks.amount));
      expect(sqlJson, contains(PiiRedactionMasks.url));
      expect(sqlJson, contains(PiiRedactionMasks.email));
      expect(sqlJson, contains(PiiRedactionMasks.phoneNumber));
      expect(sqlJson, isNot(contains('998877')));
      expect(sqlJson, isNot(contains('1250.0')));
      expect(sqlJson, isNot(contains('https://secret.bank.com')));
      expect(sqlJson, isNot(contains('secret@bank.com')));
      expect(sqlJson, isNot(contains('1800123456')));
    });

    test('State filtering logic works seamlessly with sanitized feature maps', () {
      final rawFeatures = {
        'otp': '883102',
        'amount': 2500.0,
        'hasDeadline': true,
        'deadline_minutes_remaining': 30,
      };

      final sanitizedFeatures = PiiSanitizer.sanitizeFeatureMap(rawFeatures);

      final notif = AppNotification(
        id: 'test-1',
        packageName: 'com.example.app',
        title: 'Deadline Alert',
        content: 'Your payment of Rs. 2500 is due in 30 minutes. OTP 883102',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        extractedFeatures: sanitizedFeatures,
      );

      final container = ProviderContainer();
      container.read(reviewQueueProvider.notifier).add(notif);

      final queue = container.read(reviewQueueProvider);
      expect(queue, hasLength(1));

      final deadlineNotifs = queue.where((n) => n.extractedFeatures?['hasDeadline'] == true).toList();
      expect(deadlineNotifs, hasLength(1));

      expect(notif.extractedFeatures?['otp'], equals(PiiRedactionMasks.otp));
      expect(notif.extractedFeatures?['amount'], equals(PiiRedactionMasks.amount));
    });
  });
}
