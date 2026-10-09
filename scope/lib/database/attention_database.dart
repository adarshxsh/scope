import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/tables.dart';
import 'package:scope/database/daos.dart';
import 'package:scope/database/converters.dart';

part 'attention_database.g.dart';

const String _dbKeyStorageKey = 'db_encryption_key';

/// Retrieves or generates a cryptographically random 256-bit passphrase
/// for database encryption and persists it in platform secure storage.
Future<String> getOrCreateDatabaseKey({FlutterSecureStorage? secureStorage}) async {
  final storage = secureStorage ?? const FlutterSecureStorage();
  try {
    final existingKey = await storage.read(key: _dbKeyStorageKey);
    if (existingKey != null && existingKey.isNotEmpty) {
      return existingKey;
    }

    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    final newKey = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    await storage.write(key: _dbKeyStorageKey, value: newKey);
    return newKey;
  } catch (e) {
    throw StateError('Failed to access secure storage for database encryption key: $e');
  }
}

/// Safely detects and migrates an unencrypted SQLite database file to an encrypted
/// SQLCipher database using ATTACH DATABASE or table schema/data export.
Future<void> migrateUnencryptedDatabaseIfNeeded(File dbFile, String encryptionKey) async {
  if (!dbFile.existsSync()) return;

  final bytes = await dbFile.readAsBytes();
  if (bytes.length < 16) return;

  final header = String.fromCharCodes(bytes.sublist(0, 15));
  final isUnencrypted = header == 'SQLite format 3';
  if (!isUnencrypted) return;

  final dbPath = dbFile.path;
  final unencryptedFile = File('$dbPath.unencrypted');
  if (unencryptedFile.existsSync()) {
    await unencryptedFile.delete();
  }
  await dbFile.rename(unencryptedFile.path);

  final rawDb = sqlite3.open(unencryptedFile.path);
  final escapedKey = encryptionKey.replaceAll("'", "''");

  try {
    rawDb.execute("ATTACH DATABASE '$dbPath' AS encrypted KEY '$escapedKey';");
    try {
      rawDb.execute("SELECT sqlcipher_export('encrypted');");
    } catch (_) {
      // Fallback if sqlcipher_export is not built into sqlite3 VM
      final tables = rawDb.select(
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
      );
      for (final row in tables) {
        final tableName = row['name'] as String;
        final sql = row['sql'] as String?;
        if (sql != null) {
          final createInEncrypted = sql.replaceFirstMapped(
            RegExp(r'CREATE TABLE ("?)([^"\s(]+)("?)', caseSensitive: false),
            (m) => 'CREATE TABLE encrypted."${m.group(2)}"',
          );
          rawDb.execute(createInEncrypted);
          rawDb.execute('INSERT INTO encrypted."$tableName" SELECT * FROM main."$tableName";');
        }
      }

      final indexes = rawDb.select(
        "SELECT name, sql FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%' AND sql IS NOT NULL;",
      );
      for (final row in indexes) {
        final sql = row['sql'] as String?;
        if (sql != null) {
          final createIndexInEncrypted = sql.replaceFirstMapped(
            RegExp(r'CREATE (UNIQUE )?INDEX ("?)([^"\s]+)("?)', caseSensitive: false),
            (m) => 'CREATE ${m.group(1) ?? ''}INDEX encrypted."${m.group(3)}"',
          );
          rawDb.execute(createIndexInEncrypted);
        }
      }
    }
    rawDb.execute("DETACH DATABASE encrypted;");
  } finally {
    rawDb.dispose();
    if (unencryptedFile.existsSync()) {
      await unencryptedFile.delete();
    }
  }
}

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

  factory AttentionDatabase.withStorage({
    FlutterSecureStorage? secureStorage,
    File? dbFile,
  }) {
    return AttentionDatabase(_openConnection(
      secureStorage: secureStorage,
      dbFile: dbFile,
    ));
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

QueryExecutor _openConnection({
  FlutterSecureStorage? secureStorage,
  File? dbFile,
}) {
  return LazyDatabase(() async {
    final file = dbFile ?? await _getDatabaseFile();
    final key = await getOrCreateDatabaseKey(secureStorage: secureStorage);

    await migrateUnencryptedDatabaseIfNeeded(file, key);

    return NativeDatabase(
      file,
      setup: (rawDb) {
        final escapedKey = key.replaceAll("'", "''");
        rawDb.execute("PRAGMA key = '$escapedKey';");
      },
    );
  });
}

Future<File> _getDatabaseFile() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  return File(p.join(dbFolder.path, 'attention_os.db'));
}
