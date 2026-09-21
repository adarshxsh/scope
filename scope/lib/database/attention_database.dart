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
  AttentionDatabase([QueryExecutor? executor]) : super(executor ?? openConnection());

  factory AttentionDatabase.inMemory() {
    return AttentionDatabase(NativeDatabase.memory());
  }

  factory AttentionDatabase.create({SecureKeyStorage? keyStorage, String? passphrase}) {
    return AttentionDatabase(openConnection(keyStorage: keyStorage, passphrase: passphrase));
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

/// Checks if a file is an unencrypted SQLite database by verifying the 16-byte SQLite magic header.
bool isUnencryptedSqlite(File file) {
  if (!file.existsSync() || file.lengthSync() < 16) return false;
  try {
    final raf = file.openSync(mode: FileMode.read);
    final bytes = raf.readSync(16);
    raf.closeSync();
    final header = String.fromCharCodes(bytes);
    return header.startsWith('SQLite format 3');
  } catch (_) {
    return false;
  }
}

/// Migrates an existing unencrypted database file to SQLCipher encrypted format in-place.
Future<void> migrateUnencryptedIfNeeded(File originalFile, String passphrase) async {
  if (!originalFile.existsSync()) return;
  if (!isUnencryptedSqlite(originalFile)) return;

  final tempPath = '${originalFile.path}.tmp_encrypted';
  final tempFile = File(tempPath);
  if (tempFile.existsSync()) {
    tempFile.deleteSync();
  }

  final escapedKey = passphrase.replaceAll("'", "''");
  final rawDb = sqlite3.open(originalFile.path);
  try {
    rawDb.execute("ATTACH DATABASE '${tempFile.path}' AS encrypted KEY '$escapedKey';");
    try {
      rawDb.execute("SELECT sqlcipher_export('encrypted');");
    } catch (_) {
      // Fallback schema and row copy if sqlcipher_export extension function is unavailable
      final tables = rawDb.select(
        "SELECT name, sql FROM main.sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
      );
      for (final row in tables) {
        final tableName = row['name'] as String;
        final createSql = row['sql'] as String;
        final encryptedCreateSql = createSql.replaceFirst(
          RegExp(r'CREATE TABLE (IF NOT EXISTS )?("?`?\b)'),
          'CREATE TABLE encrypted.',
        );
        rawDb.execute(encryptedCreateSql);
        rawDb.execute("INSERT INTO encrypted.$tableName SELECT * FROM main.$tableName;");
      }
    }
    rawDb.execute("DETACH DATABASE encrypted;");
  } finally {
    rawDb.dispose();
  }

  if (tempFile.existsSync() && tempFile.lengthSync() > 0) {
    originalFile.deleteSync();
    tempFile.renameSync(originalFile.path);
  }
}

QueryExecutor openConnection({SecureKeyStorage? keyStorage, String? passphrase}) {
  return LazyDatabase(() async {
    String key;
    if (passphrase != null && passphrase.isNotEmpty) {
      key = passphrase;
    } else {
      final storage = keyStorage ?? SecureKeyStorage();
      key = await storage.getOrCreatePassphrase();
    }

    final holder = PassphraseHolder(key);
    final activeKey = holder.passphrase;

    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));

    await migrateUnencryptedIfNeeded(file, activeKey);

    final db = NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$activeKey';");
      },
    );

    holder.purge();
    return db;
  });
}
