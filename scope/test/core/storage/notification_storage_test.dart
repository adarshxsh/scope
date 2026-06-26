import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/notification_storage.dart';

void main() {
  late InMemoryNotificationStorage storage;

  // Helper to create test notifications
  AppNotification makeNotification({
    required String id,
    int timestamp = 1700000000000,
    String packageName = 'com.test.app',
    String title = 'Title',
    String content = 'Content',
  }) {
    return AppNotification(
      id: id,
      packageName: packageName,
      title: title,
      content: content,
      timestamp: timestamp,
    );
  }

  setUp(() {
    storage = InMemoryNotificationStorage();
  });

  group('InMemoryNotificationStorage', () {
    group('save & getById', () {
      test('saves and retrieves a notification', () async {
        final notification = makeNotification(id: 'n1');
        await storage.save(notification);

        final result = await storage.getById('n1');
        expect(result, equals(notification));
      });

      test('returns null for non-existent id', () async {
        final result = await storage.getById('does-not-exist');
        expect(result, isNull);
      });

      test('upserts on duplicate id', () async {
        final original = makeNotification(id: 'n1', title: 'Original');
        final updated = makeNotification(id: 'n1', title: 'Updated');

        await storage.save(original);
        await storage.save(updated);

        final result = await storage.getById('n1');
        expect(result?.title, 'Updated');
        expect(await storage.count, 1);
      });
    });

    group('saveAll', () {
      test('saves multiple notifications', () async {
        final notifications = [
          makeNotification(id: 'n1'),
          makeNotification(id: 'n2'),
          makeNotification(id: 'n3'),
        ];
        await storage.saveAll(notifications);
        expect(await storage.count, 3);
      });

      test('handles empty list', () async {
        await storage.saveAll([]);
        expect(await storage.count, 0);
      });
    });

    group('getAll', () {
      test('returns empty list when storage is empty', () async {
        final result = await storage.getAll();
        expect(result, isEmpty);
      });

      test('returns notifications sorted by timestamp descending', () async {
        await storage.save(makeNotification(id: 'old', timestamp: 1000));
        await storage.save(makeNotification(id: 'mid', timestamp: 2000));
        await storage.save(makeNotification(id: 'new', timestamp: 3000));

        final result = await storage.getAll();
        expect(result.length, 3);
        expect(result[0].id, 'new');
        expect(result[1].id, 'mid');
        expect(result[2].id, 'old');
      });

      test('returns a copy (modifying result does not affect storage)', () async {
        await storage.save(makeNotification(id: 'n1'));
        final result = await storage.getAll();
        result.clear();
        expect(await storage.count, 1);
      });
    });

    group('deleteOlderThan', () {
      test('deletes notifications older than cutoff', () async {
        await storage.save(makeNotification(id: 'old', timestamp: 1000));
        await storage.save(makeNotification(id: 'mid', timestamp: 2000));
        await storage.save(makeNotification(id: 'new', timestamp: 3000));

        final deleted = await storage.deleteOlderThan(2000);
        expect(deleted, 1); // only 'old' (timestamp 1000) is < 2000
        expect(await storage.count, 2);
        expect(await storage.getById('old'), isNull);
        expect(await storage.getById('mid'), isNotNull);
        expect(await storage.getById('new'), isNotNull);
      });

      test('returns 0 when nothing to delete', () async {
        await storage.save(makeNotification(id: 'n1', timestamp: 5000));
        final deleted = await storage.deleteOlderThan(1000);
        expect(deleted, 0);
      });

      test('deletes all when cutoff is in the future', () async {
        await storage.save(makeNotification(id: 'n1', timestamp: 1000));
        await storage.save(makeNotification(id: 'n2', timestamp: 2000));
        final deleted = await storage.deleteOlderThan(9999);
        expect(deleted, 2);
        expect(await storage.count, 0);
      });
    });

    group('clear', () {
      test('removes all notifications', () async {
        await storage.saveAll([
          makeNotification(id: 'n1'),
          makeNotification(id: 'n2'),
        ]);
        expect(await storage.count, 2);

        await storage.clear();
        expect(await storage.count, 0);
        expect(await storage.getAll(), isEmpty);
      });
    });

    group('count', () {
      test('returns 0 for empty storage', () async {
        expect(await storage.count, 0);
      });

      test('returns correct count after operations', () async {
        await storage.save(makeNotification(id: 'n1'));
        expect(await storage.count, 1);

        await storage.save(makeNotification(id: 'n2'));
        expect(await storage.count, 2);

        await storage.save(makeNotification(id: 'n1', title: 'Updated'));
        expect(await storage.count, 2); // upsert, not a new entry
      });
    });
  });
}
