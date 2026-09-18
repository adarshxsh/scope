import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/utils/pii_redactor.dart';

void main() {
  group('PiiRedactor Unit Tests', () {
    test('handles null and empty input gracefully', () {
      expect(PiiRedactor.redact(null), equals(''));
      expect(PiiRedactor.redact(''), equals(''));
    });

    test('redacts email addresses correctly', () {
      final input = 'Contact us at support@scope.app for assistance.';
      final redacted = PiiRedactor.redact(input);
      expect(redacted, equals('Contact us at [REDACTED_EMAIL] for assistance.'));
    });

    test('redacts URLs correctly', () {
      final input = 'Visit https://scope.internal/auth or www.scope.com/login for details.';
      final redacted = PiiRedactor.redact(input);
      expect(redacted, equals('Visit [REDACTED_URL] or [REDACTED_URL] for details.'));
    });

    test('redacts phone numbers correctly', () {
      final input = 'Call +1 555-123-4567 or 555-987-6543 immediately.';
      final redacted = PiiRedactor.redact(input);
      expect(redacted, contains('[REDACTED_PHONE]'));
    });

    test('redacts OTP and verification codes correctly', () {
      final input = 'Your OTP code is 987654. Do not share this PIN 123456.';
      final redacted = PiiRedactor.redact(input);
      expect(redacted, contains('[REDACTED_OTP]'));
      expect(redacted, isNot(contains('987654')));
    });

    test('redacts monetary amounts correctly', () {
      final input = r'Payment of $150.00 or ₹5,000 was received.';
      final redacted = PiiRedactor.redact(input);
      expect(redacted, contains('[REDACTED_AMOUNT]'));
      expect(redacted, isNot(contains(r'$150.00')));
    });


    test('redacts bearer tokens correctly', () {
      final input = 'Authorization: bearer eyJhbGciOiJIUzI1NiI1cCI6IkpXVCJ9';
      final redacted = PiiRedactor.redact(input);
      expect(redacted, contains('[REDACTED_TOKEN]'));
    });

    test('redacts credit card numbers correctly', () {
      final input = 'Card 4111 2222 3333 4444 charged successfully.';
      final redacted = PiiRedactor.redact(input);
      expect(redacted, contains('[REDACTED_CARD]'));
      expect(redacted, isNot(contains('4111 2222 3333 4444')));
    });

    test('redactMap recursively redacts sensitive string fields', () {
      final map = {
        'title': 'OTP Verification',
        'body': 'Your code is 554433 for email test@example.com',
        'metadata': {
          'link': 'https://auth.scope.app/confirm',
          'amount': 25.5,
        },
        'tags': ['https://example.org', 'user@domain.com'],
      };

      final redactedMap = PiiRedactor.redactMap(map);
      expect(redactedMap['body'], contains('[REDACTED_OTP]'));
      expect(redactedMap['body'], contains('[REDACTED_EMAIL]'));
      expect((redactedMap['metadata'] as Map)['link'], equals('[REDACTED_URL]'));
      expect((redactedMap['tags'] as List)[0], equals('[REDACTED_URL]'));
      expect((redactedMap['tags'] as List)[1], equals('[REDACTED_EMAIL]'));
    });
  });
}
