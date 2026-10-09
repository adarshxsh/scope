import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/privacy/redactor.dart';

void main() {
  group('Redactor Privacy Utility Tests', () {
    test('redact handles null, empty, and whitespace strings correctly', () {
      expect(Redactor.redact(null), '[EMPTY]');
      expect(Redactor.redact(''), '[EMPTY]');
      expect(Redactor.redact('   '), '[EMPTY]');
    });

    test('redact masks sensitive cleartext strings while reporting character length', () {
      const title = 'WhatsApp Verification';
      const content = 'Your secret code is 882715.';

      final redactedTitle = Redactor.redact(title);
      final redactedContent = Redactor.redact(content);

      expect(redactedTitle, '[REDACTED len=21]');
      expect(redactedContent, '[REDACTED len=27]');
      expect(redactedTitle, isNot(contains(title)));
      expect(redactedContent, isNot(contains(content)));
    });

    test('redactNotificationMap sanitizes title, content, and body fields', () {
      final rawMap = <String, dynamic>{
        'packageName': 'com.bank.app',
        'title': 'Debit Alert',
        'content': 'Rs. 10,000 debited from account 1234',
        'body': 'Rs. 10,000 debited',
        'timestamp': 1700000000000,
      };

      final sanitized = Redactor.redactNotificationMap(rawMap);

      expect(sanitized['packageName'], 'com.bank.app');
      expect(sanitized['title'], '[REDACTED len=11]');
      expect(sanitized['content'], '[REDACTED len=36]');
      expect(sanitized['body'], '[REDACTED len=18]');
      expect(sanitized['timestamp'], 1700000000000);
    });
  });
}
