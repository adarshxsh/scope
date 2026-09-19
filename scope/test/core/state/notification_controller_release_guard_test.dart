import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/state/notification_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationController Release Mode Guard Tests', () {
    test('generateTestData succeeds in debug mode', () async {
      final controller = NotificationController(isReleaseMode: false);
      expect(() async => await controller.generateTestData(), returnsNormally);
      controller.dispose();
    });

    test('generateTestData throws UnsupportedError in release mode', () async {
      final controller = NotificationController(isReleaseMode: true);
      expect(
        () async => await controller.generateTestData(),
        throwsA(isA<UnsupportedError>()),
      );
      controller.dispose();
    });

    test('clearAll succeeds in debug mode', () async {
      final controller = NotificationController(isReleaseMode: false);
      expect(() async => await controller.clearAll(), returnsNormally);
      controller.dispose();
    });

    test('clearAll throws UnsupportedError in release mode', () async {
      final controller = NotificationController(isReleaseMode: true);
      expect(
        () async => await controller.clearAll(),
        throwsA(isA<UnsupportedError>()),
      );
      controller.dispose();
    });
  });
}
