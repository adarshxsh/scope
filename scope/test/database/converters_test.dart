import 'package:flutter_test/flutter_test.dart';
import 'package:scope/database/converters.dart';
import 'package:scope/core/analysis/extracted_features.dart';

void main() {
  group('JsonConverter & ExtractedFeatures PII Sanitization Tests', () {
    const converter = JsonConverter();

    test('JsonConverter.toSql sanitizes sensitive keys in extractedFeatures', () {
      final input = {
        'otp': '882715',
        'amount': 2500.50,
        'hasDeadline': true,
        'urls': ['https://example.com/reset?token=123'],
        'emails': ['user@example.com'],
        'phoneNumbers': ['18005550199'],
      };

      final sqlString = converter.toSql(input);

      expect(sqlString, isNot(contains('882715')));
      expect(sqlString, isNot(contains('2500.50')));
      expect(sqlString, isNot(contains('https://example.com/reset?token=123')));
      expect(sqlString, isNot(contains('user@example.com')));
      expect(sqlString, isNot(contains('18005550199')));

      expect(sqlString, contains('[REDACTED_OTP]'));
      expect(sqlString, contains('[REDACTED_AMOUNT]'));
      expect(sqlString, contains('[REDACTED_URL]'));
      expect(sqlString, contains('[REDACTED_EMAIL]'));
      expect(sqlString, contains('[REDACTED_PHONE]'));
    });

    test('JsonConverter.fromSql safely parses redacted JSON payload', () {
      final sqlString = '{"otp":"[REDACTED_OTP]","amount":"[REDACTED_AMOUNT]","hasDeadline":true,"urls":["[REDACTED_URL]"],"emails":["[REDACTED_EMAIL]"],"phoneNumbers":["[REDACTED_PHONE]"]}';

      final map = converter.fromSql(sqlString);
      expect(map['otp'], equals('[REDACTED_OTP]'));
      expect(map['amount'], equals('[REDACTED_AMOUNT]'));

      final features = ExtractedFeatures.fromMap(map);
      expect(features.otp, equals('[REDACTED_OTP]'));
      expect(features.amount, isNull);
      expect(features.hasDeadline, isTrue);
      expect(features.urls, equals(['[REDACTED_URL]']));
    });

    test('ExtractedFeatures.toRedactedMap converts sensitive fields to placeholders', () {
      const features = ExtractedFeatures(
        otp: '998877',
        amount: 499.99,
        hasDeadline: true,
        urls: ['https://shop.com/item'],
        emails: ['buy@shop.com'],
        phoneNumbers: ['5551234567'],
      );

      final redactedMap = features.toRedactedMap();

      expect(redactedMap['otp'], equals('[REDACTED_OTP]'));
      expect(redactedMap['amount'], equals('[REDACTED_AMOUNT]'));
      expect(redactedMap['hasDeadline'], isTrue);
      expect(redactedMap['urls'], equals(['[REDACTED_URL]']));
      expect(redactedMap['emails'], equals(['[REDACTED_EMAIL]']));
      expect(redactedMap['phoneNumbers'], equals(['[REDACTED_PHONE]']));
    });
  });
}
