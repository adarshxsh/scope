import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;
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
  AttentionDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  factory AttentionDatabase.encrypted({
    required String passphraseKey,
    File? customFile,
  }) {
    return AttentionDatabase(
        _openConnection(passphraseKey: passphraseKey, customFile: customFile));
  }

  factory AttentionDatabase.withKeyManager({
    required DatabaseKeyManager keyManager,
    File? customFile,
  }) {
    return AttentionDatabase(
        _openConnection(keyManager: keyManager, customFile: customFile));
  }

  factory AttentionDatabase.inMemory({String? passphraseKey}) {
    if (passphraseKey != null) {
      return AttentionDatabase(NativeDatabase.memory(
        setup: (rawDb) {
          rawDb.execute("PRAGMA key = '$passphraseKey';");
        },
      ));
    }
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

QueryExecutor _openConnection({
  String? passphraseKey,
  File? customFile,
  DatabaseKeyManager? keyManager,
}) {
  return LazyDatabase(() async {
    final key = passphraseKey ??
        await (keyManager ?? DatabaseKeyManager()).getOrCreatePassphrase();

    File file;
    if (customFile != null) {
      file = customFile;
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      file = File(p.join(dbFolder.path, 'attention_os.db'));
    }

    if (file.existsSync()) {
      await migrateIfUnencrypted(file, key);
    }

    return NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$key';");
      },
    );
  });
}

/// Checks if [file] exists and has an unencrypted SQLite header ("SQLite format 3").
Future<bool> isUnencryptedDatabase(File file) async {
  if (!file.existsSync()) return false;
  final length = await file.length();
  if (length < 16) return false;

  final handle = await file.open(mode: FileMode.read);
  try {
    final header = List<int>.filled(16, 0);
    await handle.readInto(header, 0, 16);
    final headerStr = String.fromCharCodes(header);
    return headerStr == 'SQLite format 3\x00';
  } finally {
    await handle.close();
  }
}

/// Migrates an unencrypted SQLite database file to SQLCipher encrypted format.
Future<void> migrateIfUnencrypted(File file, String passphraseKey) async {
  if (!await isUnencryptedDatabase(file)) {
    return;
  }

  final tempFile = File('${file.path}.migrating');
  if (tempFile.existsSync()) {
    tempFile.deleteSync();
  }

  raw_sqlite.Database? sourceDb;
  try {
    sourceDb = raw_sqlite.sqlite3.open(file.path);
    final tempPathEscaped = tempFile.path.replaceAll("'", "''");

    try {
      sourceDb.execute("ATTACH DATABASE '$tempPathEscaped' AS encrypted KEY '$passphraseKey';");
      sourceDb.execute("SELECT sqlcipher_export('encrypted');");
      sourceDb.execute("DETACH DATABASE encrypted;");
    } catch (_) {
      // Fallback if sqlcipher_export extension function is not built into the sqlite runtime
      sourceDb.execute("ATTACH DATABASE '$tempPathEscaped' AS encrypted KEY '$passphraseKey';");
      final tables = sourceDb.select(
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
      );
      for (final row in tables) {
        final tableName = row['name'] as String;
        final sql = row['sql'] as String?;
        if (sql != null) {
          sourceDb.execute("CREATE TABLE encrypted.$tableName AS SELECT * FROM main.$tableName WHERE 0;");
          sourceDb.execute("INSERT INTO encrypted.$tableName SELECT * FROM main.$tableName;");
        }
      }
      sourceDb.execute("DETACH DATABASE encrypted;");
    }
  } catch (e) {
    if (tempFile.existsSync()) {
      try {
        tempFile.deleteSync();
      } catch (_) {}
    }
    throw Exception('Failed to migrate unencrypted database to SQLCipher: $e');
  } finally {
    sourceDb?.dispose();
  }

  if (tempFile.existsSync()) {
    file.deleteSync();
    tempFile.renameSync(file.path);
  }
}


