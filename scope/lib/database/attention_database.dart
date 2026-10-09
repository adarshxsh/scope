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
  AttentionDatabase([QueryExecutor? executor])
      : super(executor ?? openConnection());

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
      await (delete(notificationsTable)
            ..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp)))
          .go();

      // 2. Delete orphaned review queue entries in a set-based query
      final orphanedQuery = delete(reviewQueueTable)
        ..where((t) {
          final hasNotification = selectOnly(notificationsTable)
            ..addColumns([notificationsTable.id]);
          return t.notificationId.isNotInQuery(hasNotification);
        });
      await orphanedQuery.go();
    });
  }
}

/// Opens an encrypted SQLCipher connection to the database.
/// Performs unencrypted database migration if an unencrypted database file exists.
QueryExecutor openConnection({
  DatabaseKeyManager? keyManager,
  File? customFile,
}) {
  return LazyDatabase(() async {
    final File file;
    if (customFile != null) {
      file = customFile;
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      file = File(p.join(dbFolder.path, 'attention_os.db'));
    }

    final km = keyManager ?? DatabaseKeyManager();
    final encryptionKey = await km.getOrCreateKey();

    // Ensure database file is initialized as encrypted or migrated from unencrypted
    await _ensureEncryptedDatabaseFile(file, encryptionKey);

    return NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$encryptionKey';");
      },
    );
  });
}

/// Helper to ensure the database file is encrypted with SQLCipher on creation or migrated if unencrypted.
Future<void> _ensureEncryptedDatabaseFile(File file, String encryptionKey) async {
  if (!file.existsSync() || file.lengthSync() == 0) {
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    try {
      final res = Process.runSync('sqlcipher', [
        file.path,
        "PRAGMA key = '$encryptionKey'; CREATE TABLE IF NOT EXISTS _sqlcipher_init (id INTEGER PRIMARY KEY);",
      ]);
      if (res.exitCode == 0 && file.existsSync() && file.lengthSync() > 0) {
        return;
      }
    } catch (_) {
      // Fallback if sqlcipher CLI is not present
    }
  } else {
    await migrateUnencryptedDatabase(file, encryptionKey);
  }
}

/// Helper to detect and migrate an existing unencrypted database file to SQLCipher format.
Future<void> migrateUnencryptedDatabase(File file, String encryptionKey) async {
  if (!file.existsSync() || file.lengthSync() == 0) {
    return;
  }

  // Check magic header bytes (unencrypted SQLite files start with "SQLite format 3\0")
  List<int> header;
  try {
    final stream = file.openRead(0, 16);
    header = await stream.first;
  } catch (_) {
    return;
  }

  if (header.length < 15) return;
  final headerStr = String.fromCharCodes(header.sublist(0, 15));
  if (!headerStr.startsWith('SQLite format 3')) {
    // Already encrypted or not a standard unencrypted SQLite file
    return;
  }

  // Migration required
  final unencCopyFile = File('${file.path}.unencrypted_bak');
  if (unencCopyFile.existsSync()) {
    unencCopyFile.deleteSync();
  }
  file.copySync(unencCopyFile.path);

  final tempEncryptedFile = File('${file.path}.migrated_enc');
  if (tempEncryptedFile.existsSync()) {
    tempEncryptedFile.deleteSync();
  }

  bool migrationSuccess = false;

  // Try SQLCipher export via CLI or ATTACH statement
  try {
    final res = Process.runSync('sqlcipher', [
      unencCopyFile.path,
      "ATTACH DATABASE '${tempEncryptedFile.path}' AS encrypted KEY '$encryptionKey'; SELECT sqlcipher_export('encrypted'); DETACH DATABASE encrypted;",
    ]);
    if (res.exitCode == 0 &&
        tempEncryptedFile.existsSync() &&
        tempEncryptedFile.lengthSync() > 0) {
      migrationSuccess = true;
    }
  } catch (_) {
    // Ignore and fallback to Dart-level copy
  }

  // Fallback: Dart-level table and row copy using sqlite3
  if (!migrationSuccess) {
    try {
      final srcDb = sqlite3.open(unencCopyFile.path);

      // Initialize destination as encrypted
      try {
        Process.runSync('sqlcipher', [
          tempEncryptedFile.path,
          "PRAGMA key = '$encryptionKey'; CREATE TABLE IF NOT EXISTS _init (id INT);",
        ]);
      } catch (_) {}

      final dstDb = sqlite3.open(tempEncryptedFile.path);
      dstDb.execute("PRAGMA key = '$encryptionKey';");

      final tables = srcDb.select(
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
      );

      for (final row in tables) {
        final tableName = row['name'] as String;
        final createSql = row['sql'] as String;
        dstDb.execute(createSql);

        final rows = srcDb.select("SELECT * FROM \"$tableName\";");
        if (rows.isNotEmpty) {
          final cols = rows.first.keys.map((c) => '"$c"').join(', ');
          final placeholders = List.filled(rows.first.length, '?').join(', ');
          final insertSql = "INSERT INTO \"$tableName\" ($cols) VALUES ($placeholders);";
          final stmt = dstDb.prepare(insertSql);
          for (final r in rows) {
            stmt.execute(r.values);
          }
          stmt.close();
        }
      }

      srcDb.close();
      dstDb.close();
      migrationSuccess = true;
    } catch (e) {
      if (tempEncryptedFile.existsSync()) {
        tempEncryptedFile.deleteSync();
      }
      rethrow;
    }
  }

  if (migrationSuccess && tempEncryptedFile.existsSync()) {
    if (file.existsSync()) {
      file.deleteSync();
    }
    tempEncryptedFile.renameSync(file.path);
    if (unencCopyFile.existsSync()) {
      unencCopyFile.deleteSync();
    }
  }
}
