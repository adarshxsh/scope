import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/smart_action_validator.dart';
import 'package:scope/core/utils/smart_actions.dart';

void main() {
  group('SmartActionValidator URL Validation Tests', () {
    setUp(() {
      SmartActionValidator.clearAuditLogs();
    });

    test('validates standard secure HTTPS and HTTP URLs', () {
      final resHttps = SmartActionValidator.validateUrl('https://example.com/portal');
      expect(resHttps.isValid, isTrue);
      expect(resHttps.status, equals(ValidationStatus.valid));
      expect(resHttps.sanitizedUrl, equals('https://example.com/portal'));

      final resHttp = SmartActionValidator.validateUrl('http://example.org/path');
      expect(resHttp.isValid, isTrue);
      expect(resHttp.status, equals(ValidationStatus.valid));
    });

    test('normalizes missing scheme domain names to HTTPS', () {
      final res = SmartActionValidator.validateUrl('www.google.com/search');
      expect(res.isValid, isTrue);
      expect(res.sanitizedUrl, equals('https://www.google.com/search'));
    });

    test('blocks dangerous URI schemes', () {
      final blocked = [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'data:text/html,<h1>Hacked</h1>',
        'content://com.example.provider/data',
        'blob:https://example.com/1234',
        'about:blank',
      ];

      for (final url in blocked) {
        final res = SmartActionValidator.validateUrl(url);
        expect(res.isValid, isFalse, reason: 'Should block $url');
        expect(res.status, equals(ValidationStatus.invalidScheme));
      }
    });

    test('blocks raw intent:// URIs and intent parameter redirection hijacking', () {
      final intentUri = 'intent://example.com#Intent;scheme=https;action=android.intent.action.VIEW;end';
      final res = SmartActionValidator.validateUrl(intentUri);
      expect(res.isValid, isFalse);
      expect(res.status, equals(ValidationStatus.blockedIntentRedirection));

      final paramHijack = 'https://example.com/login?component=com.malicious.app';
      final resParam = SmartActionValidator.validateUrl(paramHijack);
      expect(resParam.isValid, isFalse);
      expect(resParam.status, equals(ValidationStatus.blockedIntentRedirection));
    });

    test('blocks loopback IP hosts to prevent SSRF / local service abuse', () {
      final loopbacks = [
        'http://localhost:8080/admin',
        'http://127.0.0.1/status',
        'http://0.0.0.0/debug',
        'http://[::1]/info',
      ];

      for (final url in loopbacks) {
        final res = SmartActionValidator.validateUrl(url);
        expect(res.isValid, isFalse, reason: 'Should block loopback $url');
        expect(res.status, equals(ValidationStatus.blockedLoopbackHost));
      }
    });

    test('blocks embedded userinfo/credentials in URLs', () {
      final res = SmartActionValidator.validateUrl('https://admin:secret123@example.com/login');
      expect(res.isValid, isFalse);
      expect(res.status, equals(ValidationStatus.blockedUserinfo));
    });

    test('sanitizes sensitive query parameters and redacts PII', () {
      final raw = 'https://api.example.com/verify?token=abc123secret&user=john.doe@example.com&auth=jwt_xyz&normalKey=123';
      final res = SmartActionValidator.validateUrl(raw);

      expect(res.isValid, isTrue);
      expect(res.sanitizedUrl, contains('token=%5BREDACTED%5D'));
      expect(res.sanitizedUrl, contains('auth=%5BREDACTED%5D'));
      expect(res.sanitizedUrl, contains('normalKey=123'));
      expect(res.redactedUrlForAudit, contains('[REDACTED_EMAIL]'));
    });
  });

  group('SmartActionValidator Package Name Tests', () {
    test('validates legitimate package names', () {
      final res = SmartActionValidator.validatePackageName('com.example.app');
      expect(res.isValid, isTrue);
      expect(res.targetPackage, equals('com.example.app'));
    });

    test('rejects malformed or empty package names', () {
      expect(SmartActionValidator.validatePackageName(null).isValid, isFalse);
      expect(SmartActionValidator.validatePackageName('').isValid, isFalse);
      expect(SmartActionValidator.validatePackageName('invalidpackage').isValid, isFalse);
      expect(SmartActionValidator.validatePackageName('com.app; rm -rf').isValid, isFalse);
    });
  });

  group('SmartActionValidator Audit Log Memory Bounds', () {
    test('maintains audit logs bounded to max 100 entries', () {
      SmartActionValidator.clearAuditLogs();

      for (var i = 0; i < 150; i++) {
        SmartActionValidator.recordAuditLog(
          ActionAuditLogEntry(
            notificationId: 'notif-$i',
            actionType: SmartActionType.openUrl,
            status: ValidationStatus.valid,
            isAllowed: true,
            reason: 'Test entry $i',
          ),
        );
      }

      expect(SmartActionValidator.auditLogs.length, equals(100));
      expect(SmartActionValidator.auditLogs.first.notificationId, equals('notif-50'));
      expect(SmartActionValidator.auditLogs.last.notificationId, equals('notif-149'));
    });
  });

  group('SmartActionValidator Action Integration', () {
    test('evaluates SmartAction for notification correctly', () {
      final notification = AppNotification(
        id: 'test-1',
        packageName: 'com.mybank.app',
        title: 'Account Statement',
        content: 'View statement at https://mybank.com/statement',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        extractedFeatures: {
          'urls': ['https://mybank.com/statement'],
        },
      );

      final action = SmartAction(
        label: 'Open Portal',
        icon: Icons.language_outlined,
        type: SmartActionType.openUrl,
        url: 'https://mybank.com/statement',
      );

      final res = SmartActionValidator.validateAction(action, notification);
      expect(res.isValid, isTrue);
      expect(res.sanitizedUrl, equals('https://mybank.com/statement'));
    });
  });
}
