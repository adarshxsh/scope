import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  group('AppNotification', () {
    // --- Factory test data ---
    AppNotification createSample({
      String id = 'test-id-1',
      String packageName = 'com.example.app',
      String title = 'Test Title',
      String content = 'Test content body',
      int timestamp = 1700000000000,
      String? category = 'msg',
      bool isOngoing = false,
    }) {
      return AppNotification(
        id: id,
        packageName: packageName,
        title: title,
        content: content,
        timestamp: timestamp,
        category: category,
        isOngoing: isOngoing,
      );
    }

    group('constructor', () {
      test('creates instance with all required fields', () {
        final notification = createSample();
        expect(notification.id, 'test-id-1');
        expect(notification.packageName, 'com.example.app');
        expect(notification.title, 'Test Title');
        expect(notification.content, 'Test content body');
        expect(notification.timestamp, 1700000000000);
        expect(notification.category, 'msg');
        expect(notification.isOngoing, false);
      });

      test('defaults isOngoing to false', () {
        const notification = AppNotification(
          id: 'id',
          packageName: 'pkg',
          title: 'title',
          content: 'content',
          timestamp: 0,
        );
        expect(notification.isOngoing, false);
      });

      test('allows null category', () {
        final notification = createSample(category: null);
        expect(notification.category, isNull);
      });
    });

    group('toMap / fromMap', () {
      test('round-trip preserves all fields', () {
        final original = createSample();
        final map = original.toMap();
        final restored = AppNotification.fromMap(map);
        expect(restored, equals(original));
      });

      test('round-trip with null category', () {
        final original = createSample(category: null);
        final map = original.toMap();
        final restored = AppNotification.fromMap(map);
        expect(restored.category, isNull);
        expect(restored, equals(original));
      });

      test('round-trip with isOngoing true', () {
        final original = createSample(isOngoing: true);
        final map = original.toMap();
        final restored = AppNotification.fromMap(map);
        expect(restored.isOngoing, true);
        expect(restored, equals(original));
      });

      test('fromMap handles missing fields gracefully', () {
        final notification = AppNotification.fromMap({});
        expect(notification.id, '');
        expect(notification.packageName, '');
        expect(notification.title, '');
        expect(notification.content, '');
        expect(notification.timestamp, 0);
        expect(notification.category, isNull);
        expect(notification.isOngoing, false);
      });

      test('fromMap handles partial data', () {
        final notification = AppNotification.fromMap({
          'title': 'Only Title',
          'timestamp': 12345,
        });
        expect(notification.title, 'Only Title');
        expect(notification.timestamp, 12345);
        expect(notification.packageName, '');
      });

      test('toMap produces correct keys', () {
        final map = createSample().toMap();
        expect(map.keys, containsAll([
          'id', 'packageName', 'title', 'content',
          'timestamp', 'category', 'isOngoing',
        ]));
      });
    });

    group('equality', () {
      test('equal notifications have same hashCode', () {
        final a = createSample();
        final b = createSample();
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different id makes notifications unequal', () {
        final a = createSample(id: 'id-1');
        final b = createSample(id: 'id-2');
        expect(a, isNot(equals(b)));
      });

      test('different content makes notifications unequal', () {
        final a = createSample(content: 'hello');
        final b = createSample(content: 'world');
        expect(a, isNot(equals(b)));
      });
    });

    group('copyWith', () {
      test('copies with no changes produces equal object', () {
        final original = createSample();
        final copy = original.copyWith();
        expect(copy, equals(original));
      });

      test('copies with overridden fields', () {
        final original = createSample();
        final copy = original.copyWith(
          title: 'New Title',
          isOngoing: true,
        );
        expect(copy.title, 'New Title');
        expect(copy.isOngoing, true);
        // Other fields unchanged
        expect(copy.id, original.id);
        expect(copy.packageName, original.packageName);
      });
    });

    group('toString', () {
      test('contains key field values', () {
        final notification = createSample();
        final str = notification.toString();
        expect(str, contains('test-id-1'));
        expect(str, contains('com.example.app'));
        expect(str, contains('Test Title'));
      });
    });
  });
}
