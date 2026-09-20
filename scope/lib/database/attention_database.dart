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
  final PassphraseHolder? _passphraseHolder;

  AttentionDatabase([QueryExecutor? executor, String? passphrase])
      : _passphraseHolder = passphrase != null ? PassphraseHolder(passphrase) : null,
        super(executor ?? _openConnection(passphrase));

  factory AttentionDatabase.inMemory() {
    return AttentionDatabase(NativeDatabase.memory());
  }

  factory AttentionDatabase.encrypted(String passphrase) {
    return AttentionDatabase(null, passphrase);
  }

  @override
  int get schemaVersion => 1;

  @override
  Future<void> close() async {
    _passphraseHolder?.purge();
    await super.close();
  }

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

QueryExecutor _openConnection([String? explicitPassphrase]) {
  return LazyDatabase(() async {
    final passphrase = explicitPassphrase ?? await SecureKeyStorage().getOrCreatePassphrase();
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));

    await _migrateUnencryptedIfNeeded(file, passphrase);

    return NativeDatabase(
      file,
      setup: (rawDb) {
        if (passphrase.isNotEmpty) {
          rawDb.execute("PRAGMA key = '$passphrase';");
        }
      },
    );
  });
}

Future<void> _migrateUnencryptedIfNeeded(File dbFile, String passphrase) async {
  if (!dbFile.existsSync()) return;

  try {
    final bytes = await dbFile.openRead(0, 16).first;
    if (bytes.length >= 15) {
      final header = String.fromCharCodes(bytes);
      if (header.startsWith('SQLite format 3')) {
        final dbPath = dbFile.path;
        final tempEncryptedFile = File('$dbPath.tmp_encrypted');
        if (tempEncryptedFile.existsSync()) {
          await tempEncryptedFile.delete();
        }

        bool migrationSuccessful = false;
        try {
          final rawDb = sqlite3.open(dbPath);
          rawDb.execute("ATTACH DATABASE '${tempEncryptedFile.path}' AS encrypted KEY '$passphrase';");
          rawDb.execute("SELECT sqlcipher_export('encrypted');");
          rawDb.execute("DETACH DATABASE encrypted;");
          rawDb.dispose();
          migrationSuccessful = true;
        } catch (_) {}

        if (migrationSuccessful && tempEncryptedFile.existsSync()) {
          await dbFile.delete();
          await tempEncryptedFile.rename(dbPath);
        } else {
          if (tempEncryptedFile.existsSync()) {
            await tempEncryptedFile.delete();
          }
          await dbFile.delete();
        }
      }
    }
  } catch (_) {}
}
