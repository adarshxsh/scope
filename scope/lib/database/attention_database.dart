import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/tables.dart';
import 'package:scope/database/daos.dart';
import 'package:scope/database/converters.dart';
import 'package:scope/database/secure_key_storage.dart';
import 'package:scope/database/database_migrator.dart';

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
  AttentionDatabase([QueryExecutor? executor, SecureKeyStorage? keyStorage])
      : super(executor ?? _openConnection(keyStorage: keyStorage));

  factory AttentionDatabase.inMemory([String? passphrase]) {
    final key = passphrase ?? 'test_in_memory_key';
    return AttentionDatabase(
      NativeDatabase.memory(
        setup: (rawDb) {
          rawDb.execute("PRAGMA key = '$key';");
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

QueryExecutor _openConnection({SecureKeyStorage? keyStorage}) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));
    final storage = keyStorage ?? SecureKeyStorage();
    final passphrase = await storage.getOrCreatePassphrase();

    // Detect legacy plaintext database and migrate if needed
    if (await DatabaseMigrator.isPlaintextSqlite(file)) {
      await DatabaseMigrator.migratePlaintextToEncrypted(
        targetDbFile: file,
        passphrase: passphrase,
      );
    }

    return NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$passphrase';");
      },
    );
  });
}

