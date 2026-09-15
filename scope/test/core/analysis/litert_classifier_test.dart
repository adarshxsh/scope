import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LiteRtClassifier', () {
    test('initializes and attempts loading category model asset, falling back gracefully if dynamic library missing', () async {
      final classifier = LiteRtClassifier();
      
      final notif = AppNotification(
        id: '1',
        packageName: 'com.whatsapp',
        title: 'Mom',
        content: 'Hello, how are you?',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      
      expect(result.category, equals('msg'));
      expect(result.engineName, contains('fallback'));
      expect(result.score, equals(0.50));
    });

    test('fallback correctly categorizes bank alerts', () async {
      final classifier = LiteRtClassifier();
      
      final notif = AppNotification(
        id: '2',
        packageName: 'com.example.bank',
        title: 'Bank Alert',
        content: 'Your account XX3412 has been debited Rs. 2,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      
      expect(result.category, equals('finance'));
      expect(result.engineName, contains('fallback'));
    });

    test('fallback correctly categorizes promotional offers', () async {
      final classifier = LiteRtClassifier();
      
      final notif = AppNotification(
        id: '3',
        packageName: 'com.shopping.app',
        title: 'Flash Sale',
        content: 'Get 50% off on all items today only!',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      
      expect(result.category, equals('promo'));
      expect(result.engineName, contains('fallback'));
    });

    test('fallback correctly categorizes system OTP alerts', () async {
      final classifier = LiteRtClassifier();
      
      final notif = AppNotification(
        id: '4',
        packageName: 'com.auth.app',
        title: 'Verification Code',
        content: 'Your OTP code is 882715 for login verification.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      
      expect(result.category, equals('sys'));
      expect(result.engineName, contains('fallback'));
    });

    test('fallback correctly categorizes social interactions', () async {
      final classifier = LiteRtClassifier();
      
      final notif = AppNotification(
        id: '5',
        packageName: 'com.instagram.android',
        title: 'Social Notification',
        content: 'Alice liked your photo on Instagram.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      
      expect(result.category, equals('social'));
      expect(result.engineName, contains('fallback'));
    });
  });
}
