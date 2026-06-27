import 'package:drift/drift.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/converters.dart';

@DataClassName('NotificationEntry')
class NotificationsTable extends Table {
  TextColumn get id => text()();
  TextColumn get packageName => text()();
  TextColumn get title => text()();
  TextColumn get content => text()();
  IntColumn get timestamp => integer()();
  TextColumn get category => text().nullable()();
  BoolColumn get isOngoing => boolean().withDefault(const Constant(false))();
  TextColumn get priority => text().nullable()();
  RealColumn get priorityScore => real().nullable()();
  TextColumn get classifiedCategory => text().nullable()();
  TextColumn get explanation => text().nullable()();
  IntColumn get latencyMs => integer().nullable()();
  TextColumn get ruleVersion => text().nullable()();
  TextColumn get modelVersion => text().nullable()();
  TextColumn get engineVersion => text().nullable()();
  TextColumn get extractedFeatures => text().map(const JsonConverter()).nullable()();
  TextColumn get state => textEnum<ReviewState>()();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  DateTimeColumn get lastUpdated => dateTime().nullable()();
  
  // Extra persistence fields requested
  RealColumn get policyScore => real().nullable()();
  RealColumn get finalScore => real().nullable()();
  BoolColumn get reviewed => boolean().withDefault(const Constant(false))();
  BoolColumn get dismissed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ReviewQueueEntry')
class ReviewQueueTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get notificationId => text().references(NotificationsTable, #id)();
  TextColumn get priority => text()();
  DateTimeColumn get enqueueTime => dateTime()();
  DateTimeColumn get expiryTime => dateTime().nullable()();
  TextColumn get status => textEnum<ReviewState>()();
}

@DataClassName('FocusSessionEntry')
class FocusSessionsTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get sessionStart => dateTime()();
  DateTimeColumn get sessionEnd => dateTime().nullable()();
  IntColumn get interruptions => integer().withDefault(const Constant(0))();
  BoolColumn get completion => boolean().withDefault(const Constant(false))();
  IntColumn get duration => integer()(); // session duration in seconds
}

@DataClassName('DailyBriefEntry')
class DailyBriefTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text().unique()(); // YYYY-MM-DD
  IntColumn get notificationsReviewed => integer().withDefault(const Constant(0))();
  IntColumn get actionsCompleted => integer().withDefault(const Constant(0))();
  IntColumn get calendarEventsCreated => integer().withDefault(const Constant(0))();
  IntColumn get remindersCreated => integer().withDefault(const Constant(0))();
  IntColumn get archivedCount => integer().withDefault(const Constant(0))();
}
