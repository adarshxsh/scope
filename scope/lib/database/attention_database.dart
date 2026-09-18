import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/models/notification_model.dart';
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
  AttentionDatabase([QueryExecutor? executor, String? passphrase])
      : super(executor ?? _openConnection(passphrase));

  factory AttentionDatabase.inMemory({String? passphrase}) {
    return AttentionDatabase(
      NativeDatabase.memory(
        setup: (db) {
          if (passphrase != null && passphrase.isNotEmpty) {
            db.execute("PRAGMA key = '$passphrase';");
          }
        },
      ),
      passphrase,
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

/// Helper function to retrieve database passphrase from native Android com.scope.keystore channel.
Future<String?> _getPassphraseFromChannel() async {
  try {
    const channel = MethodChannel('com.scope.keystore');
    final String? passphrase = await channel.invokeMethod<String>('getDatabasePassphrase');
    return passphrase;
  } catch (e) {
    return null;
  }
}

QueryExecutor _openConnection([String? explicitPassphrase]) {
  return LazyDatabase(() async {
    final passphrase = explicitPassphrase ?? await _getPassphraseFromChannel();
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));
    return NativeDatabase(
      file,
      setup: (rawDb) {
        if (passphrase != null && passphrase.isNotEmpty) {
          rawDb.execute("PRAGMA key = '$passphrase';");
        }
      },
    );
  });
}
