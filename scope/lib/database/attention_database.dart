import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/tables.dart';
import 'package:scope/database/daos.dart';
import 'package:scope/database/converters.dart';
import 'package:scope/database/database_key_manager.dart';

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
  Future<void> runSetBasedCleanup(int cutoffTimestamp) async {
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
    });
  }
}

QueryExecutor _openConnection({DatabaseKeyManager? keyManager}) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));
    final km = keyManager ?? DatabaseKeyManager();
    final key = await km.getOrCreateKey();

    if (file.existsSync() && file.lengthSync() > 0) {
      _migrateIfNeeded(file, key);
    }

    return NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$key';");
      },
    );
  });
}

void _migrateIfNeeded(File file, String key) {
  bool isUnencrypted = false;
  try {
    final checkDb = sqlite3.open(file.path);
    try {
      checkDb.select('PRAGMA user_version;');
      isUnencrypted = true;
    } catch (_) {
      isUnencrypted = false;
    } finally {
      checkDb.close();
    }
  } catch (_) {
    isUnencrypted = false;
  }

  if (isUnencrypted) {
    final tempFile = File('${file.path}.migration.tmp');
    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }
    final migrateDb = sqlite3.open(file.path);
    try {
      migrateDb.execute("ATTACH DATABASE '${tempFile.path}' AS encrypted KEY '$key';");
      migrateDb.execute("SELECT sqlcipher_export('encrypted');");
      migrateDb.execute("DETACH DATABASE encrypted;");
    } finally {
      migrateDb.close();
    }
    if (tempFile.existsSync()) {
      file.deleteSync();
      tempFile.renameSync(file.path);
    }
  }
}

