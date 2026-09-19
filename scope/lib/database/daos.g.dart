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

mixin _$UserSettingsDaoMixin on DatabaseAccessor<AttentionDatabase> {
  $UserSettingsTableTable get userSettingsTable =>
      attachedDatabase.userSettingsTable;
  UserSettingsDaoManager get managers => UserSettingsDaoManager(this);
}

class UserSettingsDaoManager {
  final _$UserSettingsDaoMixin _db;
  UserSettingsDaoManager(this._db);
  $$UserSettingsTableTableTableManager get userSettingsTable =>
      $$UserSettingsTableTableTableManager(
        _db.attachedDatabase,
        _db.userSettingsTable,
      );
}

mixin _$InferenceTelemetryDaoMixin on DatabaseAccessor<AttentionDatabase> {
  $InferenceTelemetryTableTable get inferenceTelemetryTable =>
      attachedDatabase.inferenceTelemetryTable;
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
}
