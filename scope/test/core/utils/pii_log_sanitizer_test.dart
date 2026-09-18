import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/pii_log_sanitizer.dart';

void main() {
  group('PiiLogSanitizer Unit Tests', () {
    test('mask replaces string with redacted placeholder and character count', () {
      final masked = PiiLogSanitizer.mask('Your OTP is 882715');
      expect(masked, equals('[REDACTED (18 chars)]'));
      expect(masked.contains('882715'), isFalse);
    });

    test('mask handles null and empty input safely', () {
      expect(PiiLogSanitizer.mask(null), equals('[REDACTED]'));
      expect(PiiLogSanitizer.mask(''), equals('[REDACTED (0 chars)]'));
    });

    test('toMetadata returns label, character length, and truncated SHA-256 digest', () {
      const sensitiveTitle = 'Bank Account Alert';
      final metadata = PiiLogSanitizer.toMetadata(sensitiveTitle, label: 'title');

      expect(metadata, startsWith('[title_len=18, sha256='));
      expect(metadata, endsWith(']'));
      expect(metadata.contains('Bank Account Alert'), isFalse);
    });

    test('toMetadata handles null input safely', () {
      final metadata = PiiLogSanitizer.toMetadata(null, label: 'title');
      expect(metadata, equals('[title_len=0, sha256=null]'));
    });

    test('sha256Digest produces deterministic truncated hex output', () {
      final digest1 = PiiLogSanitizer.sha256Digest('Secret Password 123');
      final digest2 = PiiLogSanitizer.sha256Digest('Secret Password 123');

      expect(digest1, equals(digest2));
      expect(digest1.length, equals(8));
      expect(digest1, isNot(equals('Secret Password 123')));
    });

    test('sanitize supports metadata, masked, and digest modes', () {
      const text = 'Sensitive Financial Transfer';

      final masked = PiiLogSanitizer.sanitize(
        text,
        mode: SanitizationMode.masked,
      );
      final metadata = PiiLogSanitizer.sanitize(
        text,
        mode: SanitizationMode.metadata,
        label: 'content',
      );
      final digest = PiiLogSanitizer.sanitize(
        text,
        mode: SanitizationMode.digest,
      );

      expect(masked, equals('[REDACTED (28 chars)]'));
      expect(metadata, startsWith('[content_len=28, sha256='));
      expect(digest, startsWith('[sha256='));

      // Ensure no cleartext leaks
      expect(masked.contains('Financial'), isFalse);
      expect(metadata.contains('Transfer'), isFalse);
      expect(digest.contains('Sensitive'), isFalse);
    });

    test('sanitizeException redacts sensitive message payloads in exceptions', () {
      final exc = PlatformException(
        code: 'UNAUTHORIZED',
        message: 'Invalid password secret_token_999 for user john@example.com',
      );

      final sanitized = PiiLogSanitizer.sanitizeException(exc);

      expect(sanitized, startsWith('PlatformException(code: UNAUTHORIZED, message: [REDACTED (59 chars)])'));
      expect(sanitized.contains('secret_token_999'), isFalse);
      expect(sanitized.contains('john@example.com'), isFalse);
    });

    test('zero cleartext matches for sensitive notification payloads in sanitized outputs', () {
      final sensitiveNotification = AppNotification(
        id: 'notif-sens-001',
        packageName: 'com.finance.bank',
        title: r'Account balance update: $4,500.00',
        content: 'Your OTP code is 991823 for transaction #TXN987654. Password reset link inside.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final sanitizedTitle = PiiLogSanitizer.toMetadata(
        sensitiveNotification.title,
        label: 'title',
      );
      final sanitizedContent = PiiLogSanitizer.mask(
        sensitiveNotification.content,
      );
      final sanitizedReport =
          'Notification: title: "${PiiLogSanitizer.mask(sensitiveNotification.title)}", content: "$sanitizedContent"';

      final sensitiveTerms = [
        r'$4,500.00',
        '991823',
        'TXN987654',
        'Password reset link',
        'Account balance',
      ];

      for (final term in sensitiveTerms) {
        expect(
          sanitizedTitle.contains(term),
          isFalse,
          reason: 'Sanitized title contains cleartext term "$term"',
        );
        expect(
          sanitizedContent.contains(term),
          isFalse,
          reason: 'Sanitized content contains cleartext term "$term"',
        );
        expect(
          sanitizedReport.contains(term),
          isFalse,
          reason: 'Sanitized report contains cleartext term "$term"',
        );
      }
    });

    test('GhostAI inference report logging executes without leaking PII', () async {
      final sensitiveNotif = AppNotification(
        id: 'ghost-log-01',
        packageName: 'com.secure.banking',
        title: 'OTP 543210',
        content: r'Your account balance is $99,999. Do not share code 543210.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(sensitiveNotif);
      expect(result.reviewScore, isNotNull);

      final maskedTitle = PiiLogSanitizer.mask(sensitiveNotif.title);
      final maskedContent = PiiLogSanitizer.mask(sensitiveNotif.content);

      expect(maskedTitle.contains('543210'), isFalse);
      expect(maskedContent.contains('99,999'), isFalse);
    });
  });
}
