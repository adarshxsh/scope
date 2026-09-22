import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
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

  factory AttentionDatabase.withPassphrase(String passphrase) {
    return AttentionDatabase(_openConnection(overridePassphrase: passphrase));
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

void _fallbackExportToEncrypted(Database rawDb) {
  final tables = rawDb.select(
    "SELECT name, sql FROM main.sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
  );
  for (final row in tables) {
    final tableName = row['name'] as String;
    final sql = row['sql'] as String?;
    if (sql != null && sql.isNotEmpty) {
      final encryptedSql = sql.replaceFirst(
        RegExp(r'CREATE TABLE (IF NOT EXISTS )?("?\w+"?)', caseSensitive: false),
        'CREATE TABLE encrypted.$tableName',
      );
      rawDb.execute(encryptedSql);
      rawDb.execute('INSERT INTO encrypted.$tableName SELECT * FROM main.$tableName;');
    }
  }

  final indexes = rawDb.select(
    "SELECT name, sql FROM main.sqlite_master WHERE type='index' AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%';",
  );
  for (final row in indexes) {
    final indexName = row['name'] as String;
    final sql = row['sql'] as String?;
    if (sql != null && sql.isNotEmpty) {
      final encryptedSql = sql.replaceFirst(
        RegExp(r'CREATE INDEX (IF NOT EXISTS )?("?\w+"?)', caseSensitive: false),
        'CREATE INDEX encrypted.$indexName',
      );
      rawDb.execute(encryptedSql);
    }
  }
}

Future<void> migrateUnencryptedIfNeeded(File file, String passphrase) async {
  if (!await file.exists()) return;

  final raf = await file.open(mode: FileMode.read);
  final headerBytes = await raf.read(16);
  await raf.close();

  const sqliteHeader = [83, 81, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0];
  if (headerBytes.length < 16) return;

  bool isUnencrypted = true;
  for (int i = 0; i < 16; i++) {
    if (headerBytes[i] != sqliteHeader[i]) {
      isUnencrypted = false;
      break;
    }
  }

  if (!isUnencrypted) return;

  final tempPath = p.join(file.parent.path, 'attention_os_encrypted.db');
  final tempFile = File(tempPath);
  if (await tempFile.exists()) {
    await tempFile.delete();
  }

  final rawDb = sqlite3.open(file.path);
  try {
    rawDb.execute("ATTACH DATABASE '$tempPath' AS encrypted KEY '$passphrase';");
    try {
      rawDb.execute("SELECT sqlcipher_export('encrypted');");
    } on SqliteException catch (e) {
      if (e.message.contains('no such function: sqlcipher_export')) {
        _fallbackExportToEncrypted(rawDb);
      } else {
        rethrow;
      }
    }
    rawDb.execute("DETACH DATABASE encrypted;");
  } finally {
    rawDb.dispose();
  }

  await file.delete();
  await tempFile.rename(file.path);
}

QueryExecutor _openConnection({String? overridePassphrase, FlutterSecureStorage? storage}) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));

    final passphrase = overridePassphrase ?? await SecureKeyStorage.getOrCreatePassphrase(storage: storage);

    if (await file.exists()) {
      await migrateUnencryptedIfNeeded(file, passphrase);
    }

    final rawDb = sqlite3.open(file.path);
    return NativeDatabase.opened(
      rawDb,
      setup: (db) {
        db.execute("PRAGMA key = '$passphrase';");
      },
    );
  });
}

