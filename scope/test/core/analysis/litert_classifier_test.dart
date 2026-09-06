import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LiteRtClassifier', () {
    test('initializes and falls back gracefully to heuristic classifier when asset loading fails', () async {
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
      expect(result.matchedSignals.first, contains('Model asset invalid or uninitialized'));
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
      expect(result.score, equals(0.50));
    });

    test('fallback correctly categorizes promo, social, and system OTP notifications', () async {
      final classifier = LiteRtClassifier();

      final promoNotif = AppNotification(
        id: '3',
        packageName: 'com.myntra.android',
        title: 'Flash Sale',
        content: 'Get 50% discount on shoes today!',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      final promoResult = await classifier.analyze(promoNotif);
      expect(promoResult.category, equals('promo'));
      expect(promoResult.score, equals(0.50));

      final socialNotif = AppNotification(
        id: '4',
        packageName: 'com.instagram.android',
        title: 'New Like',
        content: 'John liked your photo.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      final socialResult = await classifier.analyze(socialNotif);
      expect(socialResult.category, equals('social'));

      final sysNotif = AppNotification(
        id: '5',
        packageName: 'com.google.android.gms',
        title: 'Verification Code',
        content: 'Your OTP is 982134 for sign in.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      final sysResult = await classifier.analyze(sysNotif);
      expect(sysResult.category, equals('sys'));
    });
  });
}
