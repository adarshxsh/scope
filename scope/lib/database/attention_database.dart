import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/tables.dart';
import 'package:scope/database/daos.dart';
import 'package:scope/database/converters.dart';
import 'package:scope/database/security_key_manager.dart';

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
  AttentionDatabase([QueryExecutor? executor, String? passphrase])
      : super(executor ?? _openConnection(passphrase: passphrase));

  factory AttentionDatabase.inMemory() {
    return AttentionDatabase(NativeDatabase.memory());
  }

  factory AttentionDatabase.encrypted(String passphrase, {File? file}) {
    return AttentionDatabase(
      _openConnection(passphrase: passphrase, overrideFile: file),
    );
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

QueryExecutor _openConnection({String? passphrase, File? overrideFile}) {
  return LazyDatabase(() async {
    final File file;
    if (overrideFile != null) {
      file = overrideFile;
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      file = File(p.join(dbFolder.path, 'attention_os.db'));
    }

    final String key = passphrase ?? await SecurityKeyManager.getDatabaseKey();

    // Migration and safe re-initialization check (Requirement 4)
    if (await file.exists() && file.lengthSync() >= 16) {
      await _ensureDatabaseEncrypted(file, key);
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

/// Safely migrates an unencrypted SQLite database file to an encrypted SQLCipher container,
/// or safely re-initializes if unencrypted file is corrupt or migration fails.
Future<void> _ensureDatabaseEncrypted(File file, String key) async {
  try {
    final bytes = await file.readAsBytes();
    if (bytes.length < 16) return;
    final header = String.fromCharCodes(bytes.sublist(0, 15));
    if (header != 'SQLite format 3') {
      // Already encrypted
      return;
    }

    // Unencrypted SQLite file detected. Migrate data to encrypted SQLCipher container.
    final tempEncrypted = File('${file.path}.migrating');
    if (await tempEncrypted.exists()) {
      await tempEncrypted.delete();
    }

    sqlite.Database? rawUnencryptedDb;
    try {
      rawUnencryptedDb = sqlite.sqlite3.open(file.path);
      final escapedKey = key.replaceAll("'", "''");
      rawUnencryptedDb.execute(
        "ATTACH DATABASE '${tempEncrypted.path}' AS encrypted KEY '$escapedKey';",
      );
      rawUnencryptedDb.execute("SELECT sqlcipher_export('encrypted');");
      rawUnencryptedDb.execute("DETACH DATABASE encrypted;");
      rawUnencryptedDb.close();
      rawUnencryptedDb = null;

      if (await tempEncrypted.exists() && tempEncrypted.lengthSync() > 0) {
        await file.delete();
        await tempEncrypted.rename(file.path);
      } else {
        throw Exception('Migration output file is empty or missing');
      }
    } catch (_) {
      rawUnencryptedDb?.close();
      if (await tempEncrypted.exists()) {
        await tempEncrypted.delete();
      }
      // Failsafe re-initialization: remove unencrypted plaintext file
      if (await file.exists()) {
        await file.delete();
      }
    }
  } catch (_) {
    // If file inspection fails, attempt safe removal of raw file
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}
