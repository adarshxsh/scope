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
import 'package:scope/database/secure_key_service.dart';

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

  factory AttentionDatabase.withPassphrase({required String passphrase, File? file}) {
    return AttentionDatabase(_openConnection(passphrase: passphrase, dbFile: file));
  }

  factory AttentionDatabase.inMemory() {
    return AttentionDatabase(NativeDatabase.memory());
  }

  factory AttentionDatabase.inMemoryEncrypted(String passphrase) {
    return AttentionDatabase(
      NativeDatabase.memory(
        setup: (rawDb) {
          rawDb.execute("PRAGMA key = '${passphrase.replaceAll("'", "''")}';");
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

QueryExecutor _openConnection({
  String? passphrase,
  SecureKeyService? secureKeyService,
  File? dbFile,
}) {
  return LazyDatabase(() async {
    final key = passphrase ?? await (secureKeyService ?? SecureKeyService()).getOrCreatePassphrase();
    final file = dbFile ?? File(p.join((await getApplicationDocumentsDirectory()).path, 'attention_os.db'));

    await migrateUnencryptedDatabaseIfNeeded(file, key);

    return NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '${key.replaceAll("'", "''")}';");
      },
    );
  });
}

/// Checks if SQLCipher is supported in the current SQLite environment.
bool isSqlCipherAvailable() {
  Database? db;
  try {
    db = sqlite3.openInMemory();
    final rows = db.select('PRAGMA cipher_version;');
    return rows.isNotEmpty;
  } catch (_) {
    return false;
  } finally {
    try {
      db?.close();
    } catch (_) {}
  }
}

/// Detects if an existing database file is unencrypted, migrates it using
/// sqlcipher_export into an encrypted SQLCipher database, and purges legacy plain-text artifacts.
Future<void> migrateUnencryptedDatabaseIfNeeded(File dbFile, String passphrase) async {
  if (!dbFile.existsSync()) return;

  bool isUnencrypted = false;
  Database? testDb;
  try {
    testDb = sqlite3.open(dbFile.path);
    testDb.select('PRAGMA user_version;');
    isUnencrypted = true;
  } catch (_) {
    isUnencrypted = false;
  } finally {
    try {
      testDb?.close();
    } catch (_) {}
  }

  if (!isUnencrypted) return;

  final tempEncryptedFile = File(p.join(dbFile.parent.path, 'attention_os_migrating.db'));
  if (tempEncryptedFile.existsSync()) {
    tempEncryptedFile.deleteSync();
  }

  Database? unencryptedDb;
  try {
    unencryptedDb = sqlite3.open(dbFile.path);
    final escapedPath = tempEncryptedFile.path.replaceAll("'", "''");
    final escapedKey = passphrase.replaceAll("'", "''");

    unencryptedDb.execute("ATTACH DATABASE '$escapedPath' AS encrypted KEY '$escapedKey';");

    try {
      unencryptedDb.execute("SELECT sqlcipher_export('encrypted');");
    } on SqliteException catch (e) {
      if (e.message.contains('no such function: sqlcipher_export')) {
        final tables = unencryptedDb.select("SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';");
        for (final row in tables) {
          final name = row['name'] as String;
          final sql = row['sql'] as String;
          if (sql.isNotEmpty) {
            unencryptedDb.execute(sql.replaceFirst('CREATE TABLE ', 'CREATE TABLE encrypted.'));
            unencryptedDb.execute('INSERT INTO encrypted.$name SELECT * FROM main.$name;');
          }
        }
      } else {
        rethrow;
      }
    }

    unencryptedDb.execute("DETACH DATABASE encrypted;");
  } finally {
    try {
      unencryptedDb?.close();
    } catch (_) {}
  }

  // Purge original plain-text database file and any sidecar files
  if (dbFile.existsSync()) {
    dbFile.deleteSync();
  }
  final walFile = File('${dbFile.path}-wal');
  if (walFile.existsSync()) walFile.deleteSync();
  final shmFile = File('${dbFile.path}-shm');
  if (shmFile.existsSync()) shmFile.deleteSync();
  final journalFile = File('${dbFile.path}-journal');
  if (journalFile.existsSync()) journalFile.deleteSync();

  // Replace original file with newly encrypted database
  if (tempEncryptedFile.existsSync()) {
    tempEncryptedFile.renameSync(dbFile.path);
  }
}
