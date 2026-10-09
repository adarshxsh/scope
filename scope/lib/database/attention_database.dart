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

  /// Runs a single-step atomic transaction to clean up expired notifications
  /// and any orphaned review queue entries, avoiding main-thread loops.
  /// Also compacts the database by calling VACUUM to release unused disk space.
  Future<void> runSetBasedCleanup(int cutoffTimestamp) async {
    try {
      await transaction(() async {
        // 1. Delete expired notifications based on cutoff timestamp
        await (delete(notificationsTable)..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp))).go();

        // 2. Delete orphaned review queue entries in a set-based query
        final orphanedQuery = delete(reviewQueueTable)..where((t) {
          final hasNotification = selectOnly(notificationsTable)
            ..addColumns([notificationsTable.id]);
          return t.notificationId.isNotInQuery(hasNotification);
        });
        await orphanedQuery.go();

        // 3. Delete old focus sessions (> 90 days)
        final sessionCutoff = DateTime.now().subtract(const Duration(days: 90));
        await (delete(focusSessionsTable)..where((t) => t.sessionStart.isSmallerThanValue(sessionCutoff))).go();

        // 4. Delete old daily brief entries (> 365 days)
        final briefCutoffDate = DateTime.now().subtract(const Duration(days: 365)).toIso8601String().substring(0, 10);
        await (delete(dailyBriefTable)..where((t) => t.date.isSmallerThanValue(briefCutoffDate))).go();
      });

      // Execute VACUUM outside transaction to compact DB and reclaim freed disk pages
      await compact();
    } catch (_) {
      // Absorb isolated exception during background cleanup
    }
  }

  /// Compacts SQLite database storage using VACUUM outside transaction.
  Future<void> compact() async {
    try {
      await customStatement('VACUUM;');
    } catch (_) {
      // Absorb exceptions if database is in-memory or busy
    }
  }
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));
    return NativeDatabase(file, setup: (rawDb) {
      rawDb.execute('PRAGMA auto_vacuum = FULL;');
      rawDb.execute('PRAGMA journal_mode = WAL;');
      rawDb.execute('PRAGMA synchronous = NORMAL;');
    });
  });
}
