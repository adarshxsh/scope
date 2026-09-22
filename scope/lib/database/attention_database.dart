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

/// Opens an encrypted SQLCipher database connection using a passphrase retrieved from secure storage.
QueryExecutor openDatabaseConnection({String? passphrase, SecureKeyStorage? keyStorage}) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));

    final storage = keyStorage ?? SecureKeyStorage();
    final key = passphrase ?? await storage.getOrCreateDatabasePassphrase();

    await migrateUnencryptedIfNeeded(file, key);

    final rawDb = sqlite3.open(file.path);
    final escapedKey = key.replaceAll("'", "''");
    rawDb.execute("PRAGMA key = '$escapedKey';");
    return NativeDatabase.opened(rawDb);
  });
}

QueryExecutor _openConnection() {
  return openDatabaseConnection();
}

/// Automatically migrates an unencrypted SQLite database file to SQLCipher encrypted format.
Future<void> migrateUnencryptedIfNeeded(File dbFile, String passphrase) async {
  if (!dbFile.existsSync() || dbFile.lengthSync() < 16) {
    return;
  }

  List<int> bytes = [];
  try {
    final stream = dbFile.openRead(0, 16);
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      if (bytes.length >= 16) break;
    }
  } catch (_) {
    return;
  }

  final sqliteHeader = [83, 81, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0];
  if (bytes.length < 16) return;

  bool isUnencrypted = true;
  for (int i = 0; i < 16; i++) {
    if (bytes[i] != sqliteHeader[i]) {
      isUnencrypted = false;
      break;
    }
  }

  if (!isUnencrypted) {
    return;
  }

  // Database file is unencrypted. Export to temporary SQLCipher database with passphrase.
  final tempFile = File('${dbFile.path}.tmp');
  if (tempFile.existsSync()) {
    tempFile.deleteSync();
  }

  final rawDb = sqlite3.open(dbFile.path);
  try {
    final tempPathEscaped = tempFile.path.replaceAll("'", "''");
    final keyEscaped = passphrase.replaceAll("'", "''");
    rawDb.execute("ATTACH DATABASE '$tempPathEscaped' AS encrypted KEY '$keyEscaped';");
    try {
      rawDb.execute("SELECT sqlcipher_export('encrypted');");
    } on SqliteException catch (e) {
      if (e.message.contains('no such function: sqlcipher_export')) {
        final tables = rawDb.select("SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';");
        for (final table in tables) {
          final tableName = table['name'] as String;
          final sql = table['sql'] as String?;
          if (sql != null) {
            rawDb.execute("CREATE TABLE encrypted.$tableName AS SELECT * FROM main.$tableName WHERE 0;");
            rawDb.execute("INSERT INTO encrypted.$tableName SELECT * FROM main.$tableName;");
          }
        }
      } else {
        rethrow;
      }
    }
    rawDb.execute("DETACH DATABASE encrypted;");
  } finally {
    rawDb.dispose();
  }

  if (tempFile.existsSync()) {
    dbFile.deleteSync();
    tempFile.renameSync(dbFile.path);
  }
}
