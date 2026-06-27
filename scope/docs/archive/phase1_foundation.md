# Phase 1: Foundation & Ingestion — Documentation

## Overview

Phase 1 establishes the **notification capture pipeline**: raw Android notifications flow from the OS → Kotlin service → MethodChannel bridge → Flutter UI.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   ANDROID OS                         │
│  ┌─────────────────────────────────────────────┐    │
│  │  Notification System (StatusBarNotification)  │    │
│  └──────────────────┬──────────────────────────┘    │
│                     │ onNotificationPosted()         │
│  ┌──────────────────▼──────────────────────────┐    │
│  │  NotificationCollectorService               │    │
│  │  (NotificationListenerService)               │    │
│  │  - Extracts: title, content, package, time   │    │
│  │  - Queues to: ConcurrentLinkedQueue          │    │
│  └──────────────────┬──────────────────────────┘    │
│                     │ drainQueue()                    │
│  ┌──────────────────▼──────────────────────────┐    │
│  │  MainActivity                                │    │
│  │  - MethodChannel("com.scope.notifications")  │    │
│  │  - Handles: getNotifications,                │    │
│  │    isListenerEnabled, openNotificationSettings│    │
│  └──────────────────┬──────────────────────────┘    │
└─────────────────────┼───────────────────────────────┘
                      │ MethodChannel
┌─────────────────────┼───────────────────────────────┐
│                FLUTTER / DART                        │
│  ┌──────────────────▼──────────────────────────┐    │
│  │  NotificationBridge                          │    │
│  │  - Wraps MethodChannel                       │    │
│  │  - Parses Map → AppNotification              │    │
│  │  - Injectable for testing                    │    │
│  └──────────────────┬──────────────────────────┘    │
│                     │                                │
│  ┌──────────────────▼──────────────────────────┐    │
│  │  InMemoryNotificationStorage                 │    │
│  │  - save() / getAll() / deleteOlderThan()     │    │
│  │  - Implements NotificationStorage interface  │    │
│  │  - Swappable to SQLite/Drift later           │    │
│  └──────────────────┬──────────────────────────┘    │
│                     │                                │
│  ┌──────────────────▼──────────────────────────┐    │
│  │  NotificationFeedScreen                      │    │
│  │  - Polls bridge every 3 seconds              │    │
│  │  - Displays notification cards               │    │
│  │  - Shows permission banner if needed         │    │
│  └─────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

## Files Added / Modified

### Dart (Flutter) — `lib/`

| File | Purpose |
|---|---|
| `lib/main.dart` | **MODIFIED** — App entry point, replaced counter demo with AttentionOS root |
| `lib/core/models/notification_model.dart` | **NEW** — `AppNotification` data class with serialization |
| `lib/core/storage/notification_storage.dart` | **NEW** — Abstract `NotificationStorage` interface + `InMemoryNotificationStorage` |
| `lib/core/bridge/notification_bridge.dart` | **NEW** — Flutter ↔ Kotlin `MethodChannel` wrapper |
| `lib/core/testing/test_notification_generator.dart` | **NEW** — Dart-native mock notification generator (bypasses Android self-notification block) |
| `lib/screens/notification_feed_screen.dart` | **NEW** — Minimal notification list UI with permission banner and test button |

### Kotlin (Android) — `android/app/src/main/kotlin/com/scope/attentions/`

| File | Purpose |
|---|---|
| `MainActivity.kt` | **NEW** — MethodChannel handler for Flutter bridge |
| `NotificationData.kt` | **NEW** — Kotlin data class mirroring Dart model |
| `NotificationCollectorService.kt` | **NEW** — `NotificationListenerService` that captures notifications |
| `TestNotificationSender.kt` | **NEW** — Native Android utility to trigger real OS notifications for testing |

### Android Config

| File | Purpose |
|---|---|
| `AndroidManifest.xml` | **MODIFIED** — Added service declaration + `POST_NOTIFICATIONS` permission |
| `build.gradle.kts` | **MODIFIED** — Package renamed to `com.scope.attentions`, `minSdk = 26` |

### Tests — `test/`

| File | Purpose |
|---|---|
| `test/core/models/notification_model_test.dart` | Serialization, equality, copyWith, edge cases |
| `test/core/storage/notification_storage_test.dart` | CRUD, sorting, upsert, deleteOlderThan |
| `test/core/bridge/notification_bridge_test.dart` | Mocked MethodChannel, parsing, error handling |
| `test/screens/notification_feed_screen_test.dart` | Widget tests: empty state, permission banner, cards |

## How to Test

### Run All Flutter Tests
```bash
flutter test
```

### Run Individual Test Files
```bash
flutter test test/core/models/notification_model_test.dart
flutter test test/core/storage/notification_storage_test.dart
flutter test test/core/bridge/notification_bridge_test.dart
flutter test test/screens/notification_feed_screen_test.dart
```

### Manual Testing on Device/Emulator
1. Run: `flutter run`
2. On the device, go to **Settings → Notifications → Notification access**
3. Enable **AttentionOS**
4. Send notifications (e.g., use another app, or send a test notification)
5. Notifications should appear in the feed within 3 seconds

## Key Design Decisions

1. **In-memory storage only** — No SQLite/Drift dependency yet. Keeps Phase 1 lean. The `NotificationStorage` interface makes swapping trivial.

2. **ConcurrentLinkedQueue on Kotlin side** — Thread-safe, lock-free queue between the listener service (runs in its own context) and the MainActivity.

3. **Polling (not push)** — The Flutter side polls every 3 seconds via timer. This is simpler than setting up an EventChannel. Can upgrade to EventChannel in a later phase if needed.

4. **Injectable dependencies** — `NotificationBridge` accepts an optional `MethodChannel`, and `NotificationFeedScreen` accepts optional `bridge` and `storage` params. This makes everything testable without Android.

5. **Defensive parsing** — `AppNotification.fromMap()` handles missing/null fields with defaults instead of crashing. This prevents the entire pipeline from breaking if Android sends a weird notification.

6. **Dart-Native Testing** — Because Android's `NotificationListenerService` cannot capture notifications posted by its own app, we use a Dart-native `TestNotificationGenerator` that builds mock notifications and injects them directly into local storage to simulate a live feed for testing.

## Known Limitations (Phase 1)

- Data is **ephemeral** — lost on app restart (in-memory storage)
- No **classification** or priority scoring (Phase 2)
- No **notification grouping** or deduplication
- UI is **minimal/functional** — polished dashboard comes in Phase 5
- **Polling interval** is hardcoded at 3 seconds
- No **error telemetry** (Phase 4)

## What Phase 2 Will Add

- LiteRT (TensorFlow Lite) integration for on-device classification
- Rule-based keyword engine for high-priority detection
- Priority levels: Critical / High / Medium / Low
- Quantized BERT-tiny model under 300MB RAM budget
