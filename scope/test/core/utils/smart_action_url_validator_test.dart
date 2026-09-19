import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/utils/smart_action_url_validator.dart';
import 'package:scope/core/utils/smart_actions.dart';

void main() {
  group('SmartActionUrlValidator Tests', () {
    test('validates standard http and https URLs', () {
      final res1 = SmartActionUrlValidator.validate('https://example.com/dashboard');
      expect(res1.isValid, isTrue);
      expect(res1.sanitizedUrl, equals('https://example.com/dashboard'));
      expect(res1.scheme, equals('https'));

      final res2 = SmartActionUrlValidator.validate('http://portal.university.edu/apply');
      expect(res2.isValid, isTrue);
      expect(res2.sanitizedUrl, equals('http://portal.university.edu/apply'));
      expect(res2.scheme, equals('http'));
    });

    test('validates payment portal deep link schemes', () {
      final res1 = SmartActionUrlValidator.validate('upi://pay?pa=merchant@bank&am=500');
      expect(res1.isValid, isTrue);
      expect(res1.scheme, equals('upi'));

      final res2 = SmartActionUrlValidator.validate('paytm://pay?amount=250');
      expect(res2.isValid, isTrue);
      expect(res2.scheme, equals('paytm'));

      final res3 = SmartActionUrlValidator.validate('phonepe://pay');
      expect(res3.isValid, isTrue);
      expect(res3.scheme, equals('phonepe'));
    });

    test('normalizes scheme-less domain URLs to https', () {
      final res1 = SmartActionUrlValidator.validate('example.com/path');
      expect(res1.isValid, isTrue);
      expect(res1.sanitizedUrl, equals('https://example.com/path'));

      final res2 = SmartActionUrlValidator.validate('www.google.com/search?q=test');
      expect(res2.isValid, isTrue);
      expect(res2.sanitizedUrl, equals('https://www.google.com/search?q=test'));
    });

    test('blocks dangerous file, javascript, data, content, and intent schemes', () {
      final fileRes = SmartActionUrlValidator.validate('file:///sdcard/passwords.txt');
      expect(fileRes.isValid, isFalse);
      expect(fileRes.wasBlocked, isTrue);
      expect(fileRes.scheme, equals('file'));

      final jsRes = SmartActionUrlValidator.validate('javascript:alert(document.cookie)');
      expect(jsRes.isValid, isFalse);
      expect(jsRes.wasBlocked, isTrue);
      expect(jsRes.scheme, equals('javascript'));

      final dataRes = SmartActionUrlValidator.validate('data:text/html;base64,PHNjcmlwdD4=');
      expect(dataRes.isValid, isFalse);
      expect(dataRes.wasBlocked, isTrue);
      expect(dataRes.scheme, equals('data'));

      final contentRes = SmartActionUrlValidator.validate('content://com.android.providers/1');
      expect(contentRes.isValid, isFalse);
      expect(contentRes.wasBlocked, isTrue);
      expect(contentRes.scheme, equals('content'));

      final intentRes = SmartActionUrlValidator.validate('intent://something#Intent;');
      expect(intentRes.isValid, isFalse);
      expect(intentRes.wasBlocked, isTrue);
      expect(intentRes.scheme, equals('intent'));

      final chromeRes = SmartActionUrlValidator.validate('chrome://flags');
      expect(chromeRes.isValid, isFalse);
      expect(chromeRes.wasBlocked, isTrue);
    });

    test('handles empty, null, or malformed URL inputs', () {
      expect(SmartActionUrlValidator.validate(null).isValid, isFalse);
      expect(SmartActionUrlValidator.validate('').isValid, isFalse);
      expect(SmartActionUrlValidator.validate('   ').isValid, isFalse);
      expect(SmartActionUrlValidator.validate('http://').isValid, isFalse);
    });

    test('redacts sensitive PII query parameters in diagnostic logging', () {
      const rawUrl = 'https://portal.com/login?auth_token=secret123&user_email=alice@example.com&ref=123';
      final redacted = SmartActionUrlValidator.redactUrl(rawUrl);

      expect(redacted, contains('auth_token='));
      expect(redacted, contains('user_email='));
      expect(redacted, contains('ref=123'));
      expect(redacted, contains('REDACTED'));
      expect(redacted, isNot(contains('secret123')));
      expect(redacted, isNot(contains('alice@example.com')));
    });

    test('logs diagnostic report without throwing exceptions', () {
      const action = SmartAction(
        label: 'Open Portal',
        icon: Icons.language,
        type: SmartActionType.openUrl,
        url: 'https://example.com/test?token=abc',
      );
      final validation = SmartActionUrlValidator.validate(action.url);

      expect(() {
        SmartActionUrlValidator.logDiagnostic(
          action: action,
          packageName: 'com.example.app',
          result: validation,
        );
      }, returnsNormally);
    });
  });
}
