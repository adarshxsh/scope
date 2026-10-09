import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/tables.dart';
import 'package:scope/database/daos.dart';
import 'package:scope/database/converters.dart';
import 'package:scope/database/database_key_vault.dart';

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

  factory AttentionDatabase.inMemory() {
    return AttentionDatabase(NativeDatabase.memory());
  }

  factory AttentionDatabase.openOnDisk(File file, {DatabaseKeyVault? keyVault}) {
    return AttentionDatabase(_openConnection(keyVault: keyVault, customFile: file));
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

QueryExecutor _openConnection({DatabaseKeyVault? keyVault, File? customFile}) {
  return LazyDatabase(() async {
    final vault = keyVault ?? DatabaseKeyVault();
    final File dbFile;
    if (customFile != null) {
      dbFile = customFile;
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      dbFile = File(p.join(dbFolder.path, 'attention_os.db'));
    }

    String passphrase;
    try {
      passphrase = await vault.getOrCreatePassphrase();
    } catch (_) {
      passphrase = await vault.generateAndSaveNewPassphrase();
    }

    return NativeDatabase(
      dbFile,
      setup: (rawDb) {
        final escapedPassphrase = passphrase.replaceAll("'", "''");
        rawDb.execute("PRAGMA key = '$escapedPassphrase';");
      },
    );
  });
}

