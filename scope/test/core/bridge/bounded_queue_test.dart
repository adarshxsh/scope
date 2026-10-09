import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  group('Bounded Queue & Sanitization Boundary Tests', () {
    test('AppNotification.fromMap sanitizes null and oversized input strings', () {
      final oversizedTitle = 'A' * 2000;
      final oversizedContent = 'B' * 5000;
      final mapWithNulls = {
        'id': 'notif_100',
        'packageName': 'com.test.app\u0000',
        'title': oversizedTitle,
        'content': oversizedContent,
        'timestamp': 1700000000000,
        'category': null,
        'isOngoing': false,
      };

      final notification = AppNotification.fromMap(mapWithNulls);

      expect(notification.packageName, 'com.test.app');
      expect(notification.title.length, 1000);
      expect(notification.content.length, 4000);
      expect(notification.category, isNull);
    });

    test('AppNotification.fromMap recovers safely from malformed map values', () {
      final malformedMap = <String, dynamic>{
        'id': 12345, // Int instead of String
        'packageName': null,
        'title': null,
        'content': null,
        'timestamp': 'invalid_timestamp', // String instead of int
      };

      final notification = AppNotification.fromMap(malformedMap);

      expect(notification.packageName, '');
      expect(notification.title, '');
      expect(notification.content, '');
      expect(notification.timestamp, 0);
    });
  });
}
