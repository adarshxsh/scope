import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/utils/url_launcher_utils.dart';

void main() {
  group('UrlLauncherUtils - Scheme Sanitization & Validation', () {
    test('permits valid HTTP and HTTPS URLs', () {
      expect(
        UrlLauncherUtils.sanitizeUrl('http://example.com/portal'),
        equals('http://example.com/portal'),
      );
      expect(
        UrlLauncherUtils.sanitizeUrl('https://scholarship.gov.in/apply'),
        equals('https://scholarship.gov.in/apply'),
      );
      expect(
        UrlLauncherUtils.isSafeUrlScheme('http://example.com/portal'),
        isTrue,
      );
      expect(
        UrlLauncherUtils.isSafeUrlScheme('https://scholarship.gov.in/apply'),
        isTrue,
      );
    });

    test('prepends https:// to domain names without scheme', () {
      expect(
        UrlLauncherUtils.sanitizeUrl('www.portal.com'),
        equals('https://www.portal.com'),
      );
      expect(
        UrlLauncherUtils.isSafeUrlScheme('www.portal.com'),
        isTrue,
      );
    });

    test('blocks non-whitelisted URI schemes (file, intent, javascript, content, ftp)', () {
      final forbiddenUrls = [
        'file:///etc/passwd',
        'file:///C:/Windows/System32/drivers/etc/hosts',
        'intent://package.name/#Intent;scheme=app;end',
        'javascript:alert(document.cookie)',
        'content://media/external/images/media/1',
        'ftp://anonymous:secret@files.example.com',
        'data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==',
      ];

      for (final url in forbiddenUrls) {
        expect(
          UrlLauncherUtils.sanitizeUrl(url),
          isNull,
          reason: 'URL $url should be blocked by scheme sanitizer',
        );
        expect(
          UrlLauncherUtils.isSafeUrlScheme(url),
          isFalse,
          reason: 'URL $url should be marked unsafe by isSafeUrlScheme',
        );
      }
    });

    test('handles null, empty, and whitespace strings gracefully', () {
      expect(UrlLauncherUtils.sanitizeUrl(null), isNull);
      expect(UrlLauncherUtils.sanitizeUrl(''), isNull);
      expect(UrlLauncherUtils.sanitizeUrl('   '), isNull);
      expect(UrlLauncherUtils.isSafeUrlScheme(null), isFalse);
      expect(UrlLauncherUtils.isSafeUrlScheme(''), isFalse);
    });
  });
}
