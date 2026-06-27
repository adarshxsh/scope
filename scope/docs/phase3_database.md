# Phase 3: Persistent Database using Drift — Documentation

## Overview

Phase 3 implements local data persistence in AttentionOS using the Drift library. All notification states, active review queues, focus session logs, and daily brief metrics are persisted on-device in a local SQLite file.

**Goal**: Seamless state recovery across application lifecycles while maintaining 100% backward compatibility and keeping existing UI and repository interfaces completely unchanged.

---

## Schema Architecture

Drift maps table definitions declared in [tables.dart](file:///Users/adarsh/Projects/personal/scope/scope/lib/database/tables.dart) into database schemas:

### 1. `NotificationsTable` (class `NotificationEntry`)
Stores every notification processed by the Ghost AI and Rule engines.
- `id` (Text, Primary Key)
- `packageName` (Text)
- `title` (Text)
- `content` (Text)
- `timestamp` (Integer)
- `category` (Text, Nullable)
- `isOngoing` (Boolean, default false)
- `priority` (Text, Nullable)
- `priorityScore` (Real, Nullable)
- `classifiedCategory` (Text, Nullable)
- `explanation` (Text, Nullable)
- `latencyMs` (Integer, Nullable)
- `ruleVersion` (Text, Nullable)
- `modelVersion` (Text, Nullable)
- `engineVersion` (Text, Nullable)
- `extractedFeatures` (Text, mapped via `JsonConverter`)
- `state` (TextEnum mapped to `ReviewState`)
- `snoozedUntil` (DateTime, Nullable)
- `lastUpdated` (DateTime, Nullable)
- `policyScore` (Real, Nullable)
- `finalScore` (Real, Nullable)
- `reviewed` (Boolean, default false)
- `dismissed` (Boolean, default false)
- `createdAt` (DateTime, default current time)

### 2. `ReviewQueueTable` (class `ReviewQueueEntry`)
Tracks active pending review queue items and historical status states.
- `id` (Integer, Primary Key, Auto-Increment)
- `notificationId` (Text, Foreign Key referencing `NotificationsTable.id`)
- `priority` (Text)
- `enqueueTime` (DateTime)
- `expiryTime` (DateTime, Nullable)
- `status` (TextEnum mapped to `ReviewState`)

### 3. `FocusSessionsTable` (class `FocusSessionEntry`)
Logs focus review session metrics.
- `id` (Integer, Primary Key, Auto-Increment)
- `sessionStart` (DateTime)
- `sessionEnd` (DateTime, Nullable)
- `interruptions` (Integer, default 0)
- `completion` (Boolean, default false)
- `duration` (Integer, seconds)

### 4. `DailyBriefTable` (class `DailyBriefEntry`)
Logs daily aggregated briefs.
- `id` (Integer, Primary Key, Auto-Increment)
- `date` (Text, Unique, formatted as `YYYY-MM-DD`)
- `notificationsReviewed` (Integer, default 0)
- `actionsCompleted` (Integer, default 0)
- `calendarEventsCreated` (Integer, default 0)
- `remindersCreated` (Integer, default 0)
- `archivedCount` (Integer, default 0)

---

## Data Flow Pipeline

We introduced `DriftNotificationStorage` mapping the domain model `AppNotification` to the database representation `NotificationEntry`:

```
Notification Capture (Kotlin bridge)
       ↓
NotificationController.fetchNotifications()
       ↓
DriftNotificationStorage.save()
       ↓
SQLite (attention_os.db via NotificationsTable)
       ↓
Riverpod State Notifiers (ReviewQueueNotifier)
```

---

## Startup Recovery

1. Upon app startup, the constructor of `NotificationController` triggers `_loadInitialNotifications()`.
2. It fetches all stored entries from `DriftNotificationStorage.getAll()`.
3. It loads the items into `ReviewQueueNotifier` directly via `notifier.load(list)`.
4. It calls `notifier.rescore()`, which:
   - Evaluates whether snoozed notifications have finished their snooze duration and resets them to `ACTIVE`.
   - Runs lookup predictions on current rules.

---

## Background Auto-Cleanup Policy

Pruning routines execute periodically inside the polling timer loop:
- **Notification Expire**: Deletes notifications older than 7 days from `NotificationsTable` (`deleteOlderThan(cutoffTimestamp)`).
- **Pruning**: Deletes review queue entries that no longer reference any active notifications.
- **Error Handling**: Wrapped in silent try-catch blocks to prevent user-facing exceptions from disrupting the feed screen.

---

## Verification & Tests

We wrote 6 robust tests inside [database_test.dart](file:///Users/adarsh/Projects/personal/scope/scope/test/database/database_test.dart) covering:
1. Basic inserts and lookups by ID.
2. Upsert behaviors on ID collisions (ensuring updates overwrite rows cleanly).
3. Review queue state changes and status updates.
4. Focus session logs and session duration completions.
5. Daily statistics aggregates and metric increments.
6. Auto-cleanup cutoff timestamps.

### Test Execution
```bash
flutter test test/database/database_test.dart # Passes 6/6 tests
flutter test                                 # Passes 111/111 project tests
```
