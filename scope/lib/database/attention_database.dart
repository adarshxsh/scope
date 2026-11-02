import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/tables.dart';
import 'package:scope/database/daos.dart';
import 'package:scope/database/converters.dart';

part 'attention_database.g.dart';

void setupSqlCipher() {
  if (Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux, () {
      try {
        return DynamicLibrary.open('libsqlcipher.so');
      } catch (_) {
        try {
          return DynamicLibrary.open('libsqlcipher.so.1');
        } catch (_) {
          return DynamicLibrary.open('libsqlcipher.so.0');
        }
      }
    });
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

QueryExecutor _openConnection({FlutterSecureStorage? storage}) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));
    return openConnectionForFile(file, storage: storage);
  });
}

Future<QueryExecutor> openConnectionForFile(File file, {FlutterSecureStorage? storage}) async {
  setupSqlCipher();
  final secureStorage = storage ?? const FlutterSecureStorage();
  final passphrase = await getOrCreatePassphrase(secureStorage);

  if (await file.exists()) {
    await migrateUnencryptedDatabaseIfNeeded(file, passphrase);
  }

  return NativeDatabase(
    file,
    setup: (rawDb) {
      rawDb.execute("PRAGMA key = '$passphrase';");
    },
  );
}

Future<String> getOrCreatePassphrase(FlutterSecureStorage storage) async {
  const storageKey = 'attention_db_passphrase';
  String? key = await storage.read(key: storageKey);
  if (key == null || key.isEmpty) {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    key = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await storage.write(key: storageKey, value: key);
  }
  return key;
}

Future<bool> isUnencryptedSqlite(File file) async {
  if (!await file.exists()) return false;
  final length = await file.length();
  if (length < 16) return false;

  final handle = await file.open(mode: FileMode.read);
  try {
    final header = await handle.read(16);
    if (header.length < 16) return false;
    const sqliteHeader = [
      0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00
    ];
    for (int i = 0; i < 16; i++) {
      if (header[i] != sqliteHeader[i]) return false;
    }
    return true;
  } finally {
    await handle.close();
  }
}

Future<void> migrateUnencryptedDatabaseIfNeeded(File file, String passphrase) async {
  if (await isUnencryptedSqlite(file)) {
    setupSqlCipher();
    final tempFilePath = '${file.path}.encrypted.tmp';
    final tempFile = File(tempFilePath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final rawDb = sqlite3.open(file.path);
    try {
      rawDb.execute("ATTACH DATABASE '$tempFilePath' AS encrypted KEY '$passphrase';");
      rawDb.execute("SELECT sqlcipher_export('encrypted');");
      rawDb.execute("DETACH DATABASE encrypted;");
    } finally {
      rawDb.dispose();
    }

    if (await tempFile.exists()) {
      await tempFile.rename(file.path);
    }
  }
}
