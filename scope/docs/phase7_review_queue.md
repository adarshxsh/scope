# Phase 7: Review Queue Engine & Active Panel Sync — Documentation

## Overview

Phase 7 implements the complete **Review Queue engine** inside AttentionOS, managing notifications after ML predictions and adding synchronization with active notifications in the Android panel.

**Goal**: Seamlessly organize review queues, support snoozing/archiving, auto-expire obsolete notifications (OTPs/deadlines/reminders), merge duplicates at both the Android and Flutter layers, and sort active queues.

---

## State Transition Architecture

Every notification in the Review Queue follows a standard state machine represented by the `ReviewState` enum:

- `ACTIVE`: Available for review in the active feed.
- `SNOOZED`: Temporarily hidden from the review feed until `snoozedUntil` duration has elapsed.
- `REVIEWED`: Completed/acted upon.
- `EXPIRED`: Auto-expired (e.g. elapsed OTP codes or passed relative deadlines).
- `ARCHIVED`: Archived / completed finance actions.

```
       [Posted/Synced]
              ↓
         ┌────┴────┐
         ▼         ▼
    [ACTIVE] ◄───[SNOOZED]
         │ (un-snooze)
         ├─────────────────┬────────────────┐
         ▼                 ▼                ▼
    [REVIEWED]        [EXPIRED]        [ARCHIVED]
```

---

## Key Components

### 1. Model Updates (`AppNotification`)
- Added `state` (defaults to `ACTIVE`), `snoozedUntil` (DateTime?), and `lastUpdated` (DateTime?) to `AppNotification` in [notification_model.dart](file:///Users/adarsh/Projects/personal/scope/scope/lib/core/models/notification_model.dart).
- Added `_parseReviewState` helper function to handle safe deserialization without casting/timing exceptions.

### 2. Riverpod State Engine (`providers.dart`)
- **`ReviewQueueNotifier`**: StateNotifier holding the full list of `AppNotification`s. Implements queue management APIs:
  - `add(notification)`: Inserts notification or merges duplicates (resets state to `ACTIVE`, clears snooze, updates lastUpdated).
  - `archive(id)` / `expire(id)` / `reviewed(id)` / `updateState(id, state)`: Transitions review states.
  - `snooze(id, duration)`: Transitions state to `SNOOZED` and stores `snoozedUntil` time.
  - `rescore()`: Loops through active items to recalculate priority scores via `GhostAI.predict()`, un-snoozes items whose duration has elapsed, auto-expires OTPs/deadlines, and auto-archives completed payment reminders.
- **`sortedReviewQueueProvider`**: Derived provider that filters out non-active items and sorts the active `QueueSortOrder`:
  - `reviewScore`: Highest ML score first.
  - `deadline`: Closest deadline (minutes remaining) first, non-deadlines last.
  - `lastUpdated`: Newest updated/acted-on items first.
- **`providerContainer`**: Global provider container access point initialized lazily to bridge the legacy `ChangeNotifier` cleanly.

### 3. Legacy Controller Synchronization
- Updated `NotificationController` to listen to Riverpod's `reviewQueueProvider` to automatically sync the notifications list and trigger UI updates (`notifyListeners()`).
- Delegated actions like `archive()`, `complete()`, and `snooze()` to Riverpod notifier state changes.

---

## Ingestion & Panel Deduplication

To satisfy the **no redundancy / duplicate** requirement when listening to both upcoming notifications and existing notification panel items, we implemented a dual-layer deduplication system:

### Layer 1: Native Android Service (`NotificationCollectorService.kt`)
- Updated `onListenerConnected()` to query existing system notifications (`activeNotifications`) upon service start.
- Created `addSbnToQueue()`: checks if a notification with matching content (`packageName`, `title`, and `content`) already exists in the static queue. If found, it skips adding it to prevent redundant MethodChannel logs.

### Layer 2: Flutter Ingestion (`NotificationController.fetchNotifications()`)
- When fetching notifications, `fetchNotifications()` checks raw incoming notifications against existing records in storage:
  - If a matching notification (same package, title, content) is found in storage, it **reuses the original ID** for analysis and storage.
  - When saved via `_storage.saveAll()`, it performs a database overwrite/upsert on the ID instead of creating a redundant row.
  - During same-batch ingestion, duplicates are also filtered out.
- This maintains clean, duplicate-free database storage and queue states while preserving test-specific duplication behaviors.

---

## Auto-Expiry & Cleanup Rules (`rescore()`)

When `rescore()` runs, it scans active/snoozed notifications and performs:

1. **Un-Snoozing**: If `now.isAfter(snoozedUntil!)`, the state transitions back to `ACTIVE`.
2. **OTP Auto-Expiry**: If the notification is classified as OTP (regex/text match) and the look-again score drops to `0.0` (typically 5 minutes after timestamp), state transitions to `EXPIRED`.
3. **Deadline Expiry**: If a relative meeting/task deadline has elapsed (score drops to `0.0`), state transitions to `EXPIRED`.
4. **Completed Finance Cleanups**: If the notification relates to finance (contains payment, bill, amount keywords) and content contains completion terms (`completed`, `done`, `successful`), the item transitions to `ARCHIVED`.

---

## Verification & Test Suite

We wrote and executed a comprehensive unit test suite in [review_queue_test.dart](file:///Users/adarsh/Projects/personal/scope/scope/test/core/state/review_queue_test.dart) verifying all state machines, sorting orders, auto-cleanup logic, and controller sync behaviors.

### Unit Tests Run
All **105 tests** are fully green:
```bash
flutter test test/core/state/review_queue_test.dart # Passes 16/16 Review Queue tests
flutter test                                      # Passes 105/105 project tests
```
