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

const String kDatabasePassphraseKey = 'sqlcipher_db_passphrase';

/// Retrieves an existing 256-bit passphrase from secure storage, or generates and saves a new one.
Future<String> getOrCreateDatabasePassphrase([FlutterSecureStorage? storage]) async {
  final secureStorage = storage ?? const FlutterSecureStorage();
  final existingKey = await secureStorage.read(key: kDatabasePassphraseKey);
  if (existingKey != null && existingKey.isNotEmpty) {
    return existingKey;
  }

  // Generate a cryptographically secure 256-bit passphrase (32 random bytes -> 64 hex chars)
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  final passphrase = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  await secureStorage.write(key: kDatabasePassphraseKey, value: passphrase);
  return passphrase;
}

/// Migrates an unencrypted SQLite database file to an encrypted SQLCipher database using sqlcipher_export.
void migrateUnencryptedToEncrypted(File dbFile, String passphrase) {
  final tempPath = '${dbFile.path}.tmp';
  final tempFile = File(tempPath);
  if (tempFile.existsSync()) {
    tempFile.deleteSync();
  }

  final rawDb = sqlite3.open(dbFile.path);
  try {
    rawDb.execute("ATTACH DATABASE '$tempPath' AS encrypted KEY '$passphrase';");
    rawDb.execute("SELECT sqlcipher_export('encrypted');");
    rawDb.execute("DETACH DATABASE encrypted;");
  } finally {
    rawDb.close();
  }

  tempFile.renameSync(dbFile.path);
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

  factory AttentionDatabase.encrypted({FlutterSecureStorage? secureStorage, String? customPassphrase, File? file}) {
    return AttentionDatabase(_openConnection(secureStorage: secureStorage, customPassphrase: customPassphrase, customFile: file));
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

QueryExecutor _openConnection({FlutterSecureStorage? secureStorage, String? customPassphrase, File? customFile}) {
  return LazyDatabase(() async {
    final File file;
    if (customFile != null) {
      file = customFile;
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      file = File(p.join(dbFolder.path, 'attention_os.db'));
    }

    final passphrase = customPassphrase ?? await getOrCreateDatabasePassphrase(secureStorage);

    if (await file.exists()) {
      bool isUnencrypted = false;
      try {
        final testDb = sqlite3.open(file.path);
        testDb.select('SELECT count(*) FROM sqlite_master;');
        testDb.close();
        isUnencrypted = true;
      } catch (_) {
        isUnencrypted = false;
      }

      if (isUnencrypted) {
        migrateUnencryptedToEncrypted(file, passphrase);
      }
    }

    return NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$passphrase';");
      },
    );
  });
}

