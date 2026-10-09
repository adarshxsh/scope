// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daos.dart';

// ignore_for_file: type=lint
mixin _$NotificationDaoMixin on DatabaseAccessor<AttentionDatabase> {
  $NotificationsTableTable get notificationsTable =>
      attachedDatabase.notificationsTable;
  NotificationDaoManager get managers => NotificationDaoManager(this);
}

class NotificationDaoManager {
  final _$NotificationDaoMixin _db;
  NotificationDaoManager(this._db);
  $$NotificationsTableTableTableManager get notificationsTable =>
      $$NotificationsTableTableTableManager(
        _db.attachedDatabase,
        _db.notificationsTable,
      );
}

mixin _$ReviewQueueDaoMixin on DatabaseAccessor<AttentionDatabase> {
  $NotificationsTableTable get notificationsTable =>
      attachedDatabase.notificationsTable;
  $ReviewQueueTableTable get reviewQueueTable =>
      attachedDatabase.reviewQueueTable;
  ReviewQueueDaoManager get managers => ReviewQueueDaoManager(this);
}

class ReviewQueueDaoManager {
  final _$ReviewQueueDaoMixin _db;
  ReviewQueueDaoManager(this._db);
  $$NotificationsTableTableTableManager get notificationsTable =>
      $$NotificationsTableTableTableManager(
        _db.attachedDatabase,
        _db.notificationsTable,
      );
  $$ReviewQueueTableTableTableManager get reviewQueueTable =>
      $$ReviewQueueTableTableTableManager(
        _db.attachedDatabase,
        _db.reviewQueueTable,
      );
}

mixin _$RlhfRulesDaoMixin on DatabaseAccessor<AttentionDatabase> {
  $RlhfRulesTableTable get rlhfRulesTable => attachedDatabase.rlhfRulesTable;
  RlhfRulesDaoManager get managers => RlhfRulesDaoManager(this);
}

class RlhfRulesDaoManager {
  final _$RlhfRulesDaoMixin _db;
  RlhfRulesDaoManager(this._db);
  $$RlhfRulesTableTableTableManager get rlhfRulesTable =>
      $$RlhfRulesTableTableTableManager(
        _db.attachedDatabase,
        _db.rlhfRulesTable,
      );
}

mixin _$OfflineSyncQueueDaoMixin on DatabaseAccessor<AttentionDatabase> {
  $OfflineSyncQueueTableTable get offlineSyncQueueTable =>
      attachedDatabase.offlineSyncQueueTable;
  OfflineSyncQueueDaoManager get managers => OfflineSyncQueueDaoManager(this);
}

class OfflineSyncQueueDaoManager {
  final _$OfflineSyncQueueDaoMixin _db;
  OfflineSyncQueueDaoManager(this._db);
  $$OfflineSyncQueueTableTableTableManager get offlineSyncQueueTable =>
      $$OfflineSyncQueueTableTableTableManager(
        _db.attachedDatabase,
        _db.offlineSyncQueueTable,
      );
}

mixin _$PrivacyLedgerDaoMixin on DatabaseAccessor<AttentionDatabase> {
  $PrivacyLedgerTableTable get privacyLedgerTable =>
      attachedDatabase.privacyLedgerTable;
  PrivacyLedgerDaoManager get managers => PrivacyLedgerDaoManager(this);
}

class PrivacyLedgerDaoManager {
  final _$PrivacyLedgerDaoMixin _db;
  PrivacyLedgerDaoManager(this._db);
  $$PrivacyLedgerTableTableTableManager get privacyLedgerTable =>
      $$PrivacyLedgerTableTableTableManager(
        _db.attachedDatabase,
        _db.privacyLedgerTable,
      );
}

mixin _$FocusSessionDaoMixin on DatabaseAccessor<AttentionDatabase> {
  $FocusSessionsTableTable get focusSessionsTable =>
      attachedDatabase.focusSessionsTable;
  FocusSessionDaoManager get managers => FocusSessionDaoManager(this);
}

class FocusSessionDaoManager {
  final _$FocusSessionDaoMixin _db;
  FocusSessionDaoManager(this._db);
  $$FocusSessionsTableTableTableManager get focusSessionsTable =>
      $$FocusSessionsTableTableTableManager(
        _db.attachedDatabase,
        _db.focusSessionsTable,
      );
}

mixin _$DailyBriefDaoMixin on DatabaseAccessor<AttentionDatabase> {
  $DailyBriefTableTable get dailyBriefTable => attachedDatabase.dailyBriefTable;
  DailyBriefDaoManager get managers => DailyBriefDaoManager(this);
}

class DailyBriefDaoManager {
  final _$DailyBriefDaoMixin _db;
  DailyBriefDaoManager(this._db);
  $$DailyBriefTableTableTableManager get dailyBriefTable =>
      $$DailyBriefTableTableTableManager(
        _db.attachedDatabase,
        _db.dailyBriefTable,
      );
}
