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

mixin _$InferenceTelemetryDaoMixin on DatabaseAccessor<AttentionDatabase> {
  $InferenceTelemetryTableTable get inferenceTelemetryTable =>
      attachedDatabase.inferenceTelemetryTable;
  $InferenceAuditLogsTableTable get inferenceAuditLogsTable =>
      attachedDatabase.inferenceAuditLogsTable;
  $PrivacyBudgetTableTable get privacyBudgetTable =>
      attachedDatabase.privacyBudgetTable;
  $PrivacyLedgerTableTable get privacyLedgerTable =>
      attachedDatabase.privacyLedgerTable;
  InferenceTelemetryDaoManager get managers =>
      InferenceTelemetryDaoManager(this);
}

class InferenceTelemetryDaoManager {
  final _$InferenceTelemetryDaoMixin _db;
  InferenceTelemetryDaoManager(this._db);
  $$InferenceTelemetryTableTableTableManager get inferenceTelemetryTable =>
      $$InferenceTelemetryTableTableTableManager(
        _db.attachedDatabase,
        _db.inferenceTelemetryTable,
      );
  $$InferenceAuditLogsTableTableTableManager get inferenceAuditLogsTable =>
      $$InferenceAuditLogsTableTableTableManager(
        _db.attachedDatabase,
        _db.inferenceAuditLogsTable,
      );
  $$PrivacyBudgetTableTableTableManager get privacyBudgetTable =>
      $$PrivacyBudgetTableTableTableManager(
        _db.attachedDatabase,
        _db.privacyBudgetTable,
      );
  $$PrivacyLedgerTableTableTableManager get privacyLedgerTable =>
      $$PrivacyLedgerTableTableTableManager(
        _db.attachedDatabase,
        _db.privacyLedgerTable,
      );
}
