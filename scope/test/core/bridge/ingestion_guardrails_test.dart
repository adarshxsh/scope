import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;

  setUp(() {
    channel = const MethodChannel('com.scope.notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getIngestionGuardrails') {
        return {
          'blockedPackages': <String>[],
          'allowedPackages': <String>[],
          'isWhitelistMode': false,
          'excludeOtp': true,
          'excludeFinance': true,
          'excludeHealth': false,
          'excludeSystemServices': true,
          'droppedCount': 0,
        };
      }
      if (call.method == 'updateIngestionGuardrails') {
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('IngestionGuardrails Data Model', () {
    test('toMap and fromMap round-trip preserves all fields', () {
      const original = IngestionGuardrails(
        blockedPackages: ['com.whatsapp', 'in.amazon.*'],
        allowedPackages: ['com.scope.attentions'],
        isWhitelistMode: true,
        excludeOtp: true,
        excludeFinance: true,
        excludeHealth: false,
        excludeSystemServices: true,
        droppedCount: 12,
      );

      final map = original.toMap();
      final restored = IngestionGuardrails.fromMap(map);

      expect(restored.blockedPackages, ['com.whatsapp', 'in.amazon.*']);
      expect(restored.allowedPackages, ['com.scope.attentions']);
      expect(restored.isWhitelistMode, true);
      expect(restored.excludeOtp, true);
      expect(restored.excludeFinance, true);
      expect(restored.excludeHealth, false);
      expect(restored.excludeSystemServices, true);
      expect(restored.droppedCount, 12);
    });

    test('copyWith updates specified fields only', () {
      const original = IngestionGuardrails();
      final updated = original.copyWith(
        blockedPackages: ['com.facebook.katana'],
        excludeHealth: true,
      );

      expect(updated.blockedPackages, ['com.facebook.katana']);
      expect(updated.excludeHealth, true);
      expect(updated.excludeOtp, original.excludeOtp);
      expect(updated.excludeFinance, original.excludeFinance);
    });
  });

  group('NotificationController Guardrails Ingestion Filtering', () {
    late NotificationController controller;

    setUp(() {
      controller = NotificationController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('drops blacklisted package notifications with exact match and wildcards', () async {
      await controller.updateGuardrails(
        const IngestionGuardrails(
          blockedPackages: ['com.whatsapp', 'com.bank.*'],
        ),
      );

      final whatsappNotif = AppNotification(
        id: '1',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Hello',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final bankNotif = AppNotification(
        id: '2',
        packageName: 'com.bank.mobile',
        title: 'Debit Alert',
        content: 'Your account was debited \$50',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final allowedNotif = AppNotification(
        id: '3',
        packageName: 'com.chat.app',
        title: 'Bob',
        content: 'Hey there',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(controller.shouldDropNotificationInDart(whatsappNotif), true);
      expect(controller.shouldDropNotificationInDart(bankNotif), true);
      expect(controller.shouldDropNotificationInDart(allowedNotif), false);
    });

    test('drops notifications not in whitelist when whitelist mode is active', () async {
      await controller.updateGuardrails(
        const IngestionGuardrails(
          isWhitelistMode: true,
          allowedPackages: ['com.slack', 'com.google.android.gm'],
        ),
      );

      final slackNotif = AppNotification(
        id: '1',
        packageName: 'com.slack',
        title: 'Team Chat',
        content: 'Meeting in 5 mins',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final unallowedNotif = AppNotification(
        id: '2',
        packageName: 'com.random.app',
        title: 'News Alert',
        content: 'Breaking news item',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(controller.shouldDropNotificationInDart(slackNotif), false);
      expect(controller.shouldDropNotificationInDart(unallowedNotif), true);
    });

    test('drops OTP/2FA notifications when excludeOtp is enabled', () async {
      await controller.updateGuardrails(
        const IngestionGuardrails(excludeOtp: true),
      );

      final otpNotif = AppNotification(
        id: '1',
        packageName: 'com.service.auth',
        title: 'Verification Code',
        content: 'Your verification code is 883921. Valid for 5 minutes.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(controller.shouldDropNotificationInDart(otpNotif), true);
    });

    test('drops finance/banking notifications when excludeFinance is enabled', () async {
      await controller.updateGuardrails(
        const IngestionGuardrails(excludeFinance: true),
      );

      final bankNotif = AppNotification(
        id: '1',
        packageName: 'com.paytm.app',
        title: 'Payment Received',
        content: 'Account debited Rs. 500 via UPI',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(controller.shouldDropNotificationInDart(bankNotif), true);
    });

    test('drops health notifications when excludeHealth is enabled', () async {
      await controller.updateGuardrails(
        const IngestionGuardrails(excludeHealth: true),
      );

      final healthNotif = AppNotification(
        id: '1',
        packageName: 'com.apollo.health',
        title: 'Doctor Appointment',
        content: 'Your appointment with Dr. Smith is confirmed',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(controller.shouldDropNotificationInDart(healthNotif), true);
    });

    test('drops ongoing / system service notifications when excludeSystemServices is enabled', () async {
      await controller.updateGuardrails(
        const IngestionGuardrails(excludeSystemServices: true),
      );

      final ongoingNotif = AppNotification(
        id: '1',
        packageName: 'com.spotify.music',
        title: 'Playing Music',
        content: 'Track title',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isOngoing: true,
      );

      final systemNotif = AppNotification(
        id: '2',
        packageName: 'android',
        title: 'System Update',
        content: 'Downloading update',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      expect(controller.shouldDropNotificationInDart(ongoingNotif), true);
      expect(controller.shouldDropNotificationInDart(systemNotif), true);
    });
  });
}
