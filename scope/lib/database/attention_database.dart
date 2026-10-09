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

  factory AttentionDatabase.withKey(String key, {File? customFile}) {
    return AttentionDatabase(_openConnectionWithKey(key, customFile: customFile));
  }

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
    final key = await SecureKeyStorage.getDatabaseKey();
    if (key.isEmpty) {
      throw StateError('Cannot initialize encrypted database with an empty key');
    }
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));

    if (file.existsSync()) {
      await _migrateUnencryptedToEncrypted(file, key);
    }

    return NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$key';");
      },
    );
  });
}

QueryExecutor _openConnectionWithKey(String key, {File? customFile}) {
  if (key.isEmpty) {
    throw StateError('Cannot initialize encrypted database with an empty key');
  }

  return LazyDatabase(() async {
    File file;
    if (customFile != null) {
      file = customFile;
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      file = File(p.join(dbFolder.path, 'attention_os.db'));
    }

    if (file.existsSync()) {
      await _migrateUnencryptedToEncrypted(file, key);
    }

    return NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$key';");
      },
    );
  });
}

Future<void> _migrateUnencryptedToEncrypted(File dbFile, String encryptionKey) async {
  bool isUnencrypted = false;

  final rawCheck = sqlite3.open(dbFile.path);
  try {
    rawCheck.select("SELECT count(*) FROM sqlite_master;");
    isUnencrypted = true;
  } catch (_) {
    isUnencrypted = false;
  } finally {
    rawCheck.dispose();
  }

  if (!isUnencrypted) {
    return;
  }

  final tempEncFile = File('${dbFile.path}.encrypted_tmp');
  if (tempEncFile.existsSync()) {
    tempEncFile.deleteSync();
  }

  final dbPlain = sqlite3.open(dbFile.path);
  final masterRows = dbPlain.select("SELECT type, name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';");

  final tablesData = <String, Map<String, dynamic>>{};
  for (final row in masterRows) {
    final tableName = row['name'] as String;
    final createSql = row['sql'] as String?;
    if (createSql != null && createSql.isNotEmpty) {
      final rows = dbPlain.select('SELECT * FROM "$tableName";');
      tablesData[tableName] = {
        'sql': createSql,
        'rows': rows,
      };
    }
  }
  dbPlain.dispose();

  final dbEnc = sqlite3.open(tempEncFile.path);
  dbEnc.execute("PRAGMA key = '$encryptionKey';");

  dbEnc.execute('BEGIN TRANSACTION;');
  for (final entry in tablesData.entries) {
    final tableName = entry.key;
    final createSql = entry.value['sql'] as String;
    final rows = entry.value['rows'] as ResultSet;

    dbEnc.execute(createSql);

    if (rows.isNotEmpty) {
      final columnNames = rows.columnNames;
      final placeholders = List.filled(columnNames.length, '?').join(', ');
      final colsFormatted = columnNames.map((c) => '"$c"').join(', ');
      final insertSql = 'INSERT INTO "$tableName" ($colsFormatted) VALUES ($placeholders);';

      final stmt = dbEnc.prepare(insertSql);
      for (final row in rows) {
        final rowValues = List.generate(columnNames.length, (i) => row[i]);
        stmt.execute(rowValues);
      }
      stmt.dispose();
    }
  }
  dbEnc.execute('COMMIT;');
  dbEnc.dispose();

  dbFile.deleteSync();
  tempEncFile.renameSync(dbFile.path);
}
