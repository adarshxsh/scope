import 'dart:io';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/tables.dart';
import 'package:scope/database/daos.dart';
import 'package:scope/database/converters.dart';
import 'package:scope/database/database_key_manager.dart';

part 'attention_database.g.dart';

/// Helper class for detecting and migrating legacy unencrypted SQLite databases to SQLCipher.
class DatabaseMigrator {
  /// Checks whether a given database file is an unencrypted legacy SQLite file.
  static bool isUnencryptedDatabase(File file) {
    if (!file.existsSync() || file.lengthSync() < 16) {
      return false;
    }
    try {
      final handle = file.openSync(mode: FileMode.read);
      final header = handle.readSync(16);
      handle.closeSync();
      final headerString = utf8.decode(header, allowMalformed: true);
      return headerString.startsWith('SQLite format 3');
    } catch (_) {
      return false;
    }
  }

  /// Migrates an unencrypted SQLite database to an encrypted SQLCipher database using [key].
  static Future<void> migrateToEncrypted({
    required File dbFile,
    required String key,
  }) async {
    if (!isUnencryptedDatabase(dbFile)) {
      return;
    }

    final legacyFile = File('${dbFile.path}.legacy');
    if (legacyFile.existsSync()) {
      legacyFile.deleteSync();
    }

    // Rename original file to legacy backup
    dbFile.renameSync(legacyFile.path);

    Database? legacyDb;
    try {
      legacyDb = sqlite3.open(legacyFile.path);

      final escapedDbPath = dbFile.path.replaceAll("'", "''");
      final escapedKey = key.replaceAll("'", "''");

      legacyDb.execute("ATTACH DATABASE '$escapedDbPath' AS encrypted KEY '$escapedKey';");
      legacyDb.execute("SELECT sqlcipher_export('encrypted');");
      legacyDb.execute("DETACH DATABASE encrypted;");
      legacyDb.close();
      legacyDb = null;

      // Migration succeeded, remove legacy unencrypted file
      if (legacyFile.existsSync()) {
        legacyFile.deleteSync();
      }
    } catch (e) {
      legacyDb?.close();
      // If migration failed, attempt to clean up partial output and restore legacy file
      if (dbFile.existsSync()) {
        try {
          dbFile.deleteSync();
        } catch (_) {}
      }
      if (legacyFile.existsSync()) {
        legacyFile.renameSync(dbFile.path);
      }
      rethrow;
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

  factory AttentionDatabase.withKey(String key, {File? file}) {
    if (file != null) {
      return AttentionDatabase(
        LazyDatabase(() async {
          if (file.existsSync() && DatabaseMigrator.isUnencryptedDatabase(file)) {
            await DatabaseMigrator.migrateToEncrypted(dbFile: file, key: key);
          }
          return NativeDatabase(
            file,
            setup: (rawDb) {
              final escapedKey = key.replaceAll("'", "''");
              rawDb.execute("PRAGMA key = '$escapedKey';");
            },
          );
        }),
      );
    }
    return AttentionDatabase(_openConnection(explicitKey: key));
  }

  factory AttentionDatabase.inMemory({String? key}) {
    final encryptionKey = key ?? DatabaseKeyManager.generateSecure256BitKey();
    return AttentionDatabase(
      NativeDatabase.memory(
        setup: (rawDb) {
          final escapedKey = encryptionKey.replaceAll("'", "''");
          rawDb.execute("PRAGMA key = '$escapedKey';");
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

QueryExecutor _openConnection({String? explicitKey, DatabaseKeyManager? keyManager}) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));

    final key = explicitKey ?? await (keyManager ?? DatabaseKeyManager()).getOrCreateKey();

    if (file.existsSync() && DatabaseMigrator.isUnencryptedDatabase(file)) {
      await DatabaseMigrator.migrateToEncrypted(dbFile: file, key: key);
    }

    return NativeDatabase(
      file,
      setup: (rawDb) {
        final escapedKey = key.replaceAll("'", "''");
        rawDb.execute("PRAGMA key = '$escapedKey';");
      },
    );
  });
}
