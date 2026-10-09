import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw_sqlite3;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/database_key_manager.dart';
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

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));

    final key = await DatabaseKeyManager().getOrCreateKey();

    if (await _isUnencryptedDatabase(file)) {
      await _migrateUnencryptedToEncrypted(file, key);
    }

    return NativeDatabase(
      file,
      setup: (db) {
        db.execute("PRAGMA key = '$key';");
      },
    );
  });
}

Future<bool> _isUnencryptedDatabase(File file) async {
  if (!await file.exists()) return false;
  final length = await file.length();
  if (length < 16) return false;

  try {
    final handle = await file.open(mode: FileMode.read);
    final headerBytes = await handle.read(16);
    await handle.close();
    final headerString = String.fromCharCodes(headerBytes);
    return headerString == 'SQLite format 3\x00';
  } catch (e) {
    return false;
  }
}

Future<void> _migrateUnencryptedToEncrypted(File file, String key) async {
  final tempFile = File('${file.path}.tmp_encrypted');
  if (await tempFile.exists()) {
    await tempFile.delete();
  }

  try {
    final sourceDb = raw_sqlite3.sqlite3.open(file.path);
    final targetDb = raw_sqlite3.sqlite3.open(tempFile.path);
    targetDb.execute("PRAGMA key = '$key';");

    try {
      sourceDb.execute("ATTACH DATABASE '${tempFile.path}' AS encrypted KEY '$key';");
      sourceDb.execute("SELECT sqlcipher_export('encrypted');");
      sourceDb.execute("DETACH DATABASE encrypted;");
    } catch (_) {
      final tables = sourceDb.select("SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';");
      for (final row in tables) {
        final sql = row['sql'] as String?;
        if (sql != null && sql.isNotEmpty) {
          targetDb.execute(sql);
        }
      }

      targetDb.execute("ATTACH DATABASE '${file.path}' AS unencrypted KEY '';");
      for (final row in tables) {
        final tableName = row['name'] as String;
        targetDb.execute("INSERT INTO main.$tableName SELECT * FROM unencrypted.$tableName;");
      }
      targetDb.execute("DETACH DATABASE unencrypted;");
    }

    sourceDb.dispose();
    targetDb.dispose();

    if (await tempFile.exists() && await tempFile.length() > 0) {
      await file.delete();
      await tempFile.rename(file.path);
    }
  } catch (e) {
    debugPrint('Database migration error: $e');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  }
}

