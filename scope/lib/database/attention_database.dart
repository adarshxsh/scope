import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/tables.dart';
import 'package:scope/database/daos.dart';
import 'package:scope/database/converters.dart';

part 'attention_database.g.dart';

@DriftDatabase(
  tables: [
    NotificationsTable,
    ReviewQueueTable,
    FocusSessionsTable,
    DailyBriefTable,
  ],
  daos: [
    NotificationDao,
    ReviewQueueDao,
    FocusSessionDao,
    DailyBriefDao,
  ],
)
class AttentionDatabase extends _$AttentionDatabase {
  AttentionDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  factory AttentionDatabase.inMemory() {
    return AttentionDatabase(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 1;

  /// Calculates total database storage usage in bytes.
  Future<int> getStorageUsageBytes() async {
    try {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'attention_os.db'));
      if (await file.exists()) {
        final length = await file.length();
        if (length > 0) return length;
      }
    } catch (_) {}

    // Fallback calculation summing stored notification row byte sizes
    final all = await notificationDao.getAll();
    int size = 0;
    for (final n in all) {
      size += n.id.length + n.packageName.length + n.title.length + n.content.length + 256;
      if (n.extractedFeatures != null) {
        size += n.extractedFeatures.toString().length;
      }
    }
    return size;
  }

  /// Runs a single-step atomic transaction to clean up expired notifications
  /// and any orphaned review queue entries, avoiding main-thread loops.
  Future<void> runSetBasedCleanup(int cutoffTimestamp) async {
    await transaction(() async {
      // 1. Delete expired notifications based on cutoff timestamp
      await (delete(notificationsTable)..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp))).go();

      // 2. Delete orphaned review queue entries in a set-based query
      await _deleteOrphanedReviewQueueItems();
    });
  }

  /// Runs dynamic cleanup using user preference retention duration and storage quota.
  Future<void> runDynamicCleanup({
    int retentionDays = 7,
    int storageQuotaMb = 100,
  }) async {
    await transaction(() async {
      // 1. Delete notifications older than dynamic retention cutoff
      if (retentionDays > 0) {
        final cutoff = DateTime.now().subtract(Duration(days: retentionDays)).millisecondsSinceEpoch;
        await (delete(notificationsTable)..where((t) => t.timestamp.isSmallerThanValue(cutoff))).go();
      }

      // 2. Delete orphaned review queue entries
      await _deleteOrphanedReviewQueueItems();

      // 3. Enforce storage quota using First-In, First-Out (FIFO) deletion order
      if (storageQuotaMb >= 0) {
        final maxBytes = storageQuotaMb * 1024 * 1024;
        int currentBytes = await getStorageUsageBytes();

        if (currentBytes > maxBytes) {
          final allEntries = await (select(notificationsTable)
                ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.asc)]))
              .get();

          // FIFO deletion order: prioritize non-active historical entries first (ARCHIVED, EXPIRED, REVIEWED), then ACTIVE
          final historicalEntries = allEntries
              .where((e) => e.state == ReviewState.ARCHIVED ||
                  e.state == ReviewState.EXPIRED ||
                  e.state == ReviewState.REVIEWED)
              .toList();

          final activeEntries = allEntries
              .where((e) => e.state != ReviewState.ARCHIVED &&
                  e.state != ReviewState.EXPIRED &&
                  e.state != ReviewState.REVIEWED)
              .toList();

          final deleteOrder = [...historicalEntries, ...activeEntries];

          for (final entry in deleteOrder) {
            if (currentBytes <= maxBytes) break;

            await (delete(notificationsTable)..where((t) => t.id.equals(entry.id))).go();

            final freedBytes = entry.id.length +
                entry.packageName.length +
                entry.title.length +
                entry.content.length +
                256 +
                (entry.extractedFeatures?.toString().length ?? 0);
            currentBytes = currentBytes > freedBytes ? currentBytes - freedBytes : 0;
          }

          // Clean up orphaned queue entries after quota purge
          await _deleteOrphanedReviewQueueItems();
        }
      }
    });
  }

  Future<void> _deleteOrphanedReviewQueueItems() async {
    final orphanedQuery = delete(reviewQueueTable)..where((t) {
      final hasNotification = selectOnly(notificationsTable)
        ..addColumns([notificationsTable.id]);
      return t.notificationId.isNotInQuery(hasNotification);
    });
    await orphanedQuery.go();
  }
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));
    return NativeDatabase(file);
  });
}
