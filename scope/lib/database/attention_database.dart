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
import 'package:scope/database/key_storage_service.dart';

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

  factory AttentionDatabase.onDisk({KeyStorageService? keyStorageService, String? dbPath}) {
    return AttentionDatabase(_openConnection(keyStorageService: keyStorageService, dbPath: dbPath));
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

QueryExecutor _openConnection({KeyStorageService? keyStorageService, String? dbPath}) {
  return LazyDatabase(() async {
    final keyStorage = keyStorageService ?? KeyStorageService();
    final encryptionKey = await keyStorage.getOrCreateEncryptionKey();

    final String path;
    if (dbPath != null) {
      path = dbPath;
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      path = p.join(dbFolder.path, 'attention_os.db');
    }

    final file = File(path);
    if (await file.exists()) {
      await _migrateIfUnencrypted(file, encryptionKey);
    }

    return NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$encryptionKey';");
      },
    );
  });
}

Future<void> _migrateIfUnencrypted(File dbFile, String encryptionKey) async {
  try {
    final bytes = await dbFile.openRead(0, 16).first;
    final header = String.fromCharCodes(bytes);
    if (!header.startsWith('SQLite format 3')) {
      // Already encrypted or non-standard header
      return;
    }
  } catch (_) {
    return;
  }

  final tempEncFile = File('${dbFile.path}.enc_migrated');
  if (await tempEncFile.exists()) {
    await tempEncFile.delete();
  }

  Database? oldDb;
  Database? newDb;
  try {
    oldDb = sqlite3.open(dbFile.path);
    newDb = sqlite3.open(tempEncFile.path);
    newDb.execute("PRAGMA key = '$encryptionKey';");

    final tables = oldDb.select("SELECT sql, name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';");
    newDb.execute('BEGIN TRANSACTION;');
    for (final row in tables) {
      final createSql = row['sql'] as String?;
      final tableName = row['name'] as String;
      if (createSql != null) {
        newDb.execute(createSql);
        final tableData = oldDb.select('SELECT * FROM "$tableName";');
        if (tableData.isNotEmpty) {
          final columns = tableData.first.keys;
          final placeholders = List.filled(columns.length, '?').join(', ');
          final colNames = columns.map((c) => '"$c"').join(', ');
          final insertSql = 'INSERT INTO "$tableName" ($colNames) VALUES ($placeholders);';
          final stmt = newDb.prepare(insertSql);
          for (final dataRow in tableData) {
            stmt.execute(dataRow.values);
          }
          stmt.close();
        }
      }
    }
    final userVersion = oldDb.select('PRAGMA user_version;').first.values.first as int;
    final targetVersion = userVersion > 0 ? userVersion : 1;
    newDb.execute('PRAGMA user_version = $targetVersion;');
    newDb.execute('COMMIT;');
  } catch (e) {
    if (await tempEncFile.exists()) {
      await tempEncFile.delete();
    }
    rethrow;
  } finally {
    oldDb?.close();
    newDb?.close();
  }

  // Migration complete; replace legacy unencrypted db file with encrypted db file
  final walFile = File('${dbFile.path}-wal');
  if (await walFile.exists()) await walFile.delete();
  final shmFile = File('${dbFile.path}-shm');
  if (await shmFile.exists()) await shmFile.delete();

  await dbFile.delete();
  await tempEncFile.rename(dbFile.path);
}
