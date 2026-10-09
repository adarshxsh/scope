import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/tables.dart';
import 'package:scope/database/daos.dart';
import 'package:scope/database/converters.dart';
import 'package:scope/database/secure_key_storage.dart';

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

/// Header magic bytes for unencrypted SQLite 3 databases ("SQLite format 3\0")
final Uint8List _sqlite3HeaderBytes = Uint8List.fromList([
  0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
  0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00,
]);

bool isUnencryptedSqliteFile(File file) {
  if (!file.existsSync() || file.lengthSync() < 16) {
    return false;
  }
  final bytes = file.readAsBytesSync().sublist(0, 16);
  if (bytes.length < 16) return false;
  for (int i = 0; i < 16; i++) {
    if (bytes[i] != _sqlite3HeaderBytes[i]) {
      return false;
    }
  }
  return true;
}

void migrateUnencryptedIfNeeded(File file, String passphrase) {
  if (!isUnencryptedSqliteFile(file)) {
    return;
  }

  final tempFile = File('${file.path}.tmp');
  if (tempFile.existsSync()) {
    try {
      tempFile.deleteSync();
    } catch (_) {}
  }

  final rawDb = sqlite3.sqlite3.open(file.path);
  try {
    rawDb.execute("ATTACH DATABASE '${tempFile.path}' AS encrypted KEY '$passphrase';");
    try {
      rawDb.execute("SELECT sqlcipher_export('encrypted');");
    } catch (_) {
      _fallbackExportToEncrypted(rawDb, 'encrypted');
    }
    rawDb.execute("DETACH DATABASE encrypted;");
  } finally {
    rawDb.close();
  }

  if (tempFile.existsSync()) {
    file.deleteSync();
    tempFile.renameSync(file.path);

    // Clean up auxiliary journal/WAL files
    final walFile = File('${file.path}-wal');
    if (walFile.existsSync()) walFile.deleteSync();
    final shmFile = File('${file.path}-shm');
    if (shmFile.existsSync()) shmFile.deleteSync();
    final journalFile = File('${file.path}-journal');
    if (journalFile.existsSync()) journalFile.deleteSync();
  }
}

void _fallbackExportToEncrypted(sqlite3.Database rawDb, String schemaName) {
  final tables = rawDb.select(
    "SELECT name, sql FROM main.sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';"
  );
  for (final row in tables) {
    final tableName = row['name'] as String;
    final sql = row['sql'] as String?;
    if (sql != null) {
      try {
        rawDb.execute("CREATE TABLE $schemaName.$tableName AS SELECT * FROM main.$tableName;");
      } catch (_) {}
    }
  }
  final indices = rawDb.select(
    "SELECT sql FROM main.sqlite_master WHERE type='index' AND sql IS NOT NULL;"
  );
  for (final row in indices) {
    final sql = row['sql'] as String?;
    if (sql != null) {
      try {
        rawDb.execute(sql);
      } catch (_) {}
    }
  }
}

QueryExecutor _openConnection({String? keyOverride, SecureKeyStorage? keyStorage}) {
  return LazyDatabase(() async {
    final key = keyOverride ?? await (keyStorage ?? SecureKeyStorage()).getOrCreateDatabaseKey();
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));

    migrateUnencryptedIfNeeded(file, key);

    return NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$key';");
      },
    );
  });
}
