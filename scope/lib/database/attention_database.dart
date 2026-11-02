import 'dart:convert';
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

  factory AttentionDatabase.withKey(String key, [File? file]) {
    return AttentionDatabase(_openConnection(encryptionKey: key, dbFile: file));
  }

  factory AttentionDatabase.withFile(File file, [String? key]) {
    return AttentionDatabase(_openConnection(encryptionKey: key, dbFile: file));
  }

  factory AttentionDatabase.inMemory([String? key]) {
    return AttentionDatabase(
      NativeDatabase.memory(
        setup: (db) {
          if (key != null && key.isNotEmpty) {
            db.execute("PRAGMA key = \"x'$key'\";");
          }
          db.execute('PRAGMA journal_mode = WAL;');
          db.execute('PRAGMA cipher_memory_security = ON;');
          db.execute('PRAGMA temp_store = MEMORY;');
        },
      ),
    );
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

QueryExecutor _openConnection({String? encryptionKey, File? dbFile}) {
  return LazyDatabase(() async {
    final file = dbFile ?? File(p.join((await getApplicationDocumentsDirectory()).path, 'attention_os.db'));
    final key = encryptionKey ?? await DatabaseKeyManager().getOrCreateKey();

    if (file.existsSync() && file.lengthSync() >= 16) {
      await _migrateIfUnencrypted(file, key);
    }

    return NativeDatabase(
      file,
      setup: (db) {
        db.execute("PRAGMA key = \"x'$key'\";");
        db.execute('PRAGMA journal_mode = WAL;');
        db.execute('PRAGMA cipher_memory_security = ON;');
        db.execute('PRAGMA temp_store = MEMORY;');
      },
    );
  });
}

Future<void> _migrateIfUnencrypted(File file, String key) async {
  try {
    final bytes = await file.openRead(0, 16).first;
    if (bytes.length >= 16) {
      final header = utf8.decode(bytes.sublist(0, 15), allowMalformed: true);
      if (header == 'SQLite format 3') {
        final tempPath = '${file.path}.tmp';
        final tempFile = File(tempPath);
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }

        final db = sqlite3.open(file.path);
        var exportWorked = false;
        try {
          db.execute("ATTACH DATABASE '$tempPath' AS encrypted KEY \"x'$key'\";");
          db.execute("SELECT sqlcipher_export('encrypted');");
          exportWorked = true;
        } catch (_) {
          exportWorked = false;
        }

        if (!exportWorked) {
          try {
            db.execute("DETACH DATABASE encrypted;");
          } catch (_) {}
          db.execute("ATTACH DATABASE '$tempPath' AS encrypted;");

          final tables = db.select(
            "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
          );
          for (final row in tables) {
            final tableName = row['name'] as String;
            final createSql = row['sql'] as String?;
            if (createSql != null) {
              db.execute(createSql.replaceAll('CREATE TABLE ', 'CREATE TABLE encrypted.'));
              db.execute('INSERT INTO encrypted."$tableName" SELECT * FROM main."$tableName";');
            }
          }
        }

        try {
          db.execute("DETACH DATABASE encrypted;");
        } catch (_) {}
        db.close();

        if (tempFile.existsSync()) {
          tempFile.renameSync(file.path);
        }
      }
    }
  } catch (_) {
    // If migration encounters any exception, allow database creation to continue
  }
}

