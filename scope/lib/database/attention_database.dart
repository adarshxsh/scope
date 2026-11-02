import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/security/database_key_manager.dart';
import 'package:scope/database/tables.dart';
import 'package:scope/database/daos.dart';
import 'package:scope/database/converters.dart';

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

  factory AttentionDatabase.inMemory({String? passphrase}) {
    if (passphrase != null) {
      final escapedPassphrase = passphrase.replaceAll("'", "''");
      return AttentionDatabase(NativeDatabase.memory(
        setup: (db) {
          db.execute("PRAGMA key = '$escapedPassphrase';");
        },
      ));
    }
    return AttentionDatabase(NativeDatabase.memory());
  }

  factory AttentionDatabase.encryptedFile(File file, {String? passphrase}) {
    return AttentionDatabase(_openConnection(explicitFile: file, explicitPassphrase: passphrase));
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

QueryExecutor _openConnection({File? explicitFile, String? explicitPassphrase}) {
  return LazyDatabase(() async {
    final dbFolder = explicitFile != null ? explicitFile.parent : await getApplicationDocumentsDirectory();
    final file = explicitFile ?? File(p.join(dbFolder.path, 'attention_os.db'));

    final passphrase = explicitPassphrase ?? await DatabaseKeyManager().getOrCreatePassphrase();

    await migrateUnencryptedDatabaseIfNeeded(file, passphrase);

    final escapedPassphrase = passphrase.replaceAll("'", "''");

    return NativeDatabase(
      file,
      setup: (db) {
        db.execute("PRAGMA key = '$escapedPassphrase';");
      },
    );
  });
}

/// Checks if a database file exists and is unencrypted (starts with standard SQLite header),
/// migrating it to an encrypted SQLCipher database if needed.
Future<void> migrateUnencryptedDatabaseIfNeeded(File file, String passphrase) async {
  if (!file.existsSync() || file.lengthSync() < 16) {
    return;
  }

  bool isUnencrypted = false;
  final raf = await file.open(mode: FileMode.read);
  final headerBytes = await raf.read(16);
  await raf.close();

  if (headerBytes.length == 16) {
    const sqliteHeader = [83, 81, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0];
    isUnencrypted = true;
    for (int i = 0; i < 16; i++) {
      if (headerBytes[i] != sqliteHeader[i]) {
        isUnencrypted = false;
        break;
      }
    }
  }

  if (!isUnencrypted) {
    return;
  }

  final tempEncryptedFile = File('${file.path}.tmp_encrypted');
  if (tempEncryptedFile.existsSync()) {
    tempEncryptedFile.deleteSync();
  }

  final unencryptedDb = sqlite3.open(file.path);
  try {
    final escapedPassphrase = passphrase.replaceAll("'", "''");
    unencryptedDb.execute("ATTACH DATABASE '${tempEncryptedFile.path}' AS encrypted KEY '$escapedPassphrase';");
    unencryptedDb.execute("SELECT sqlcipher_export('encrypted');");
    unencryptedDb.execute("DETACH DATABASE encrypted;");
  } finally {
    unencryptedDb.close();
  }

  if (tempEncryptedFile.existsSync()) {
    file.deleteSync();
    tempEncryptedFile.renameSync(file.path);
  }
}
