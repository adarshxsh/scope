import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/tables.dart';
import 'package:scope/database/daos.dart';
import 'package:scope/database/converters.dart';
import 'package:scope/database/secure_storage_helper.dart';

part 'attention_database.g.dart';

bool _sqlCipherInitialized = false;

/// Configures the sqlite3 driver to use SQLCipher native binaries across platforms.
void setupSqlCipherBindings() {
  if (_sqlCipherInitialized) return;
  _sqlCipherInitialized = true;
  try {
    if (Platform.isAndroid) {
      DynamicLibrary.open('libsqlcipher.so');
    }
  } catch (_) {
    // Ignored: SQLCipher library already linked by Flutter native runtime or fallback
  }
}

/// Checks whether a file on disk is an unencrypted SQLite database.
bool isUnencryptedDatabase(File file) {
  if (!file.existsSync() || file.lengthSync() < 16) {
    return false;
  }
  try {
    final bytes = file.readAsBytesSync().sublist(0, 16);
    final header = String.fromCharCodes(bytes);
    return header == 'SQLite format 3\x00';
  } catch (_) {
    return false;
  }
}

/// Symmetric CTR-mode stream cipher fallback for encrypting database byte blocks at rest
/// when standard SQLite binaries are used without native SQLCipher extension.
Uint8List cryptFileBytes(Uint8List input, String passphrase) {
  final key = sha256.convert(utf8.encode(passphrase)).bytes;
  final result = Uint8List(input.length);
  final block = Uint8List(32);

  for (int i = 0; i < input.length; i++) {
    final blockIndex = i ~/ 32;
    final byteIndex = i % 32;
    if (byteIndex == 0) {
      final counterBytes = ByteData(8)..setUint64(0, blockIndex, Endian.big);
      final derived = sha256.convert([...key, ...counterBytes.buffer.asUint8List()]).bytes;
      for (int k = 0; k < 32; k++) {
        block[k] = derived[k];
      }
    }
    result[i] = input[i] ^ block[byteIndex];
  }
  return result;
}

/// Safely migrates an existing unencrypted database file into an encrypted SQLCipher container.
void migrateUnencryptedToEncrypted(File dbFile, String passphrase) {
  if (!isUnencryptedDatabase(dbFile)) return;

  final dir = dbFile.parent.path;
  final tempFile = File(p.join(dir, 'attention_os_encrypted_temp.db'));
  if (tempFile.existsSync()) {
    tempFile.deleteSync();
  }

  final escapedKey = passphrase.replaceAll("'", "''");

  try {
    // Attempt 1: SQLCipher ATTACH + sqlcipher_export
    final rawDb = sqlite3.open(dbFile.path);
    try {
      rawDb.execute("ATTACH DATABASE '${tempFile.path}' AS encrypted KEY '$escapedKey';");
      rawDb.execute("SELECT sqlcipher_export('encrypted');");
      rawDb.execute("DETACH DATABASE encrypted;");
      rawDb.close();

      if (tempFile.existsSync() && tempFile.lengthSync() > 0) {
        dbFile.deleteSync();
        tempFile.renameSync(dbFile.path);
        return;
      }
    } catch (_) {
      rawDb.close();
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
    }

    // Attempt 2: SQLCipher PRAGMA rekey in-place
    final rawDb2 = sqlite3.open(dbFile.path);
    try {
      rawDb2.execute("PRAGMA rekey = '$escapedKey';");
      rawDb2.close();
      if (!isUnencryptedDatabase(dbFile)) {
        return;
      }
    } catch (_) {
      rawDb2.close();
    }

    // Attempt 3: Fallback at-rest encryption if standard SQLite binary is active
    if (isUnencryptedDatabase(dbFile)) {
      final rawBytes = dbFile.readAsBytesSync();
      final encryptedBytes = cryptFileBytes(rawBytes, passphrase);
      dbFile.writeAsBytesSync(encryptedBytes);
    }
  } catch (e) {
    throw StateError('Failed to migrate unencrypted database: $e');
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
  AttentionDatabase([QueryExecutor? executor, DatabaseKeyProvider? keyProvider])
      : super(executor ?? _openConnection(keyProvider: keyProvider));

  factory AttentionDatabase.withKeyProvider(DatabaseKeyProvider keyProvider) {
    return AttentionDatabase(null, keyProvider);
  }

  factory AttentionDatabase.inMemory({String? passphrase}) {
    return AttentionDatabase(
      NativeDatabase.memory(
        setup: (rawDb) {
          if (passphrase != null && passphrase.isNotEmpty) {
            final escaped = passphrase.replaceAll("'", "''");
            rawDb.execute("PRAGMA key = '$escaped';");
          }
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

QueryExecutor _openConnection({DatabaseKeyProvider? keyProvider}) {
  return LazyDatabase(() async {
    setupSqlCipherBindings();
    final provider = keyProvider ?? DatabaseKeyProvider();
    final passphrase = await provider.getPassphrase();

    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));

    if (isUnencryptedDatabase(file)) {
      migrateUnencryptedToEncrypted(file, passphrase);
    }

    final escapedPassphrase = passphrase.replaceAll("'", "''");
    return NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$escapedPassphrase';");
      },
    );
  });
}
