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
  AttentionDatabase([QueryExecutor? executor]) : super(executor ?? openConnection());

  factory AttentionDatabase.withKeyManager(DatabaseKeyManager keyManager) {
    return AttentionDatabase(openConnection(keyManager: keyManager));
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

QueryExecutor openConnection({DatabaseKeyManager? keyManager}) {
  return LazyDatabase(() async {
    final manager = keyManager ?? DatabaseKeyManager();
    final passphrase = await manager.getOrCreatePassphrase();

    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));

    if (file.existsSync() && file.lengthSync() > 0) {
      await ensureEncrypted(file, passphrase);
    }

    return NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$passphrase';");
      },
    );
  });
}

/// Detects legacy unencrypted database files and migrates them in-place using sqlcipher_export,
/// or triggers a safe recovery routine if the file cannot be decrypted.
Future<void> ensureEncrypted(File file, String passphrase) async {
  if (!file.existsSync() || file.lengthSync() == 0) return;

  Database? rawDb;
  bool isUnencrypted = false;
  try {
    rawDb = sqlite3.open(file.path);
    rawDb.select('SELECT count(*) FROM sqlite_master;');
    isUnencrypted = true;
  } catch (_) {
    isUnencrypted = false;
  }

  if (isUnencrypted && rawDb != null) {
    try {
      final tempEncPath = '${file.path}.tmp_encrypted';
      final tempEncFile = File(tempEncPath);
      if (tempEncFile.existsSync()) {
        tempEncFile.deleteSync();
      }

      rawDb.execute("ATTACH DATABASE '$tempEncPath' AS encrypted KEY '$passphrase';");
      rawDb.execute("SELECT sqlcipher_export('encrypted');");
      rawDb.execute("DETACH DATABASE encrypted;");
      rawDb.close();
      rawDb = null;

      file.deleteSync();
      tempEncFile.renameSync(file.path);
    } catch (_) {
      rawDb?.close();
      rawDb = null;
    }
  } else {
    rawDb?.close();
    rawDb = null;

    // Verify key validity and safely recover if database is corrupt or passphrase mismatch
    try {
      final testDb = sqlite3.open(file.path);
      testDb.execute("PRAGMA key = '$passphrase';");
      testDb.select('SELECT count(*) FROM sqlite_master;');
      testDb.close();
    } catch (_) {
      try {
        file.renameSync('${file.path}.bak_${DateTime.now().millisecondsSinceEpoch}');
      } catch (_) {}
    }
  }
}
