import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_provider.dart';
import 'package:scope/database/drift_notification_storage.dart';

enum QueueSortOrder {
  reviewScore,
  deadline,
  lastUpdated,
}

class ReviewQueueNotifier extends StateNotifier<List<AppNotification>> {
  final AttentionDatabase? _db;
  ReviewQueueNotifier([this._db]) : super([]);

  /// Load a list of notifications directly (used on startup recovery).
  void load(List<AppNotification> list) {
    state = list;
  }

  /// Add a notification to the review queue.
  /// Merges duplicate notifications (same packageName, title, content).
  void add(AppNotification notification) {
    final now = DateTime.now();
    final index = state.indexWhere((n) =>
        n.packageName == notification.packageName &&
        n.title == notification.title &&
        n.content == notification.content);

    AppNotification newItem;
    if (index >= 0) {
      // Merge duplicate notification
      final existing = state[index];
      newItem = notification.copyWith(
        id: existing.id, // Preserve original ID
        state: ReviewState.ACTIVE, // Reset to ACTIVE
        snoozedUntil: null, // Clear snooze
        lastUpdated: now,
      );
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == index) newItem else state[i]
      ];
    } else {
      // Add new notification
      newItem = notification.copyWith(
        state: ReviewState.ACTIVE,
        lastUpdated: now,
      );
      state = [...state, newItem];
    }

    // Persist to DB
    if (_db != null) {
      DriftNotificationStorage(_db).save(newItem);
      _saveQueueEntry(newItem);
    }
  }

  /// Remove a notification from the review queue entirely.
  void remove(String id) {
    state = state.where((n) => n.id != id).toList();
    if (_db != null) {
      _db.reviewQueueDao.deleteItem(id);
    }
  }

  /// Update a notification's fields in the queue.
  void update(AppNotification notification) {
    state = [
      for (final n in state)
        if (n.id == notification.id) notification else n
    ];
    if (_db != null) {
      DriftNotificationStorage(_db).save(notification);
      _saveQueueEntry(notification);
    }
  }

  /// Mark a notification as reviewed (transition to REVIEWED state).
  void reviewed(String id) {
    final now = DateTime.now();
    state = [
      for (final n in state)
        if (n.id == id)
          n.copyWith(state: ReviewState.REVIEWED, lastUpdated: now)
        else
          n
    ];
    if (_db != null) {
      final item = state.firstWhere((n) => n.id == id);
      DriftNotificationStorage(_db).save(item);
      _db.reviewQueueDao.updateStatus(id, ReviewState.REVIEWED);
    }
  }

  /// Manually update a notification's review state.
  void updateState(String id, ReviewState newState) {
    final now = DateTime.now();
    state = [
      for (final n in state)
        if (n.id == id)
          n.copyWith(state: newState, lastUpdated: now)
        else
          n
    ];
    if (_db != null) {
      final item = state.firstWhere((n) => n.id == id);
      DriftNotificationStorage(_db).save(item);
      _db.reviewQueueDao.updateStatus(id, newState);
    }
  }

  /// Archive a notification (transition to ARCHIVED state).
  void archive(String id) {
    final now = DateTime.now();
    state = [
      for (final n in state)
        if (n.id == id)
          n.copyWith(state: ReviewState.ARCHIVED, lastUpdated: now)
        else
          n
    ];
    if (_db != null) {
      final item = state.firstWhere((n) => n.id == id);
      DriftNotificationStorage(_db).save(item);
      _db.reviewQueueDao.updateStatus(id, ReviewState.ARCHIVED);
    }
  }

  /// Expire a notification (transition to EXPIRED state).
  void expire(String id) {
    final now = DateTime.now();
    state = [
      for (final n in state)
        if (n.id == id)
          n.copyWith(state: ReviewState.EXPIRED, lastUpdated: now)
        else
          n
    ];
    if (_db != null) {
      final item = state.firstWhere((n) => n.id == id);
      DriftNotificationStorage(_db).save(item);
      _db.reviewQueueDao.updateStatus(id, ReviewState.EXPIRED);
    }
  }

  /// Snooze a notification for a specific duration.
  void snooze(String id, Duration duration) {
    final now = DateTime.now();
    final snoozedUntil = now.add(duration);
    state = [
      for (final n in state)
        if (n.id == id)
          n.copyWith(
            state: ReviewState.SNOOZED,
            snoozedUntil: snoozedUntil,
            lastUpdated: now,
          )
        else
          n
    ];
    if (_db != null) {
      final item = state.firstWhere((n) => n.id == id);
      DriftNotificationStorage(_db).save(item);
      _saveQueueEntry(item, expiry: snoozedUntil);
    }
  }

  /// Re-scores notifications and applies auto-expiry/cleanup rules.
  Future<void> rescore() async {
    final now = DateTime.now();
    final updated = <AppNotification>[];

    for (final item in state) {
      // Don't re-score/auto-expire archived or reviewed notifications
      if (item.state == ReviewState.ARCHIVED || item.state == ReviewState.REVIEWED) {
        updated.add(item);
        continue;
      }

      // 1. Un-snooze if duration elapsed
      ReviewState currentState = item.state;
      if (currentState == ReviewState.SNOOZED &&
          item.snoozedUntil != null &&
          now.isAfter(item.snoozedUntil!)) {
        currentState = ReviewState.ACTIVE;
      }

      // 2. Perform re-scoring prediction via GhostAI
      final ghostResult = await GhostAI.predict(item);

      var updatedItem = item.copyWith(
        priorityScore: ghostResult.reviewScore,
        state: currentState,
        lastUpdated: now,
      );

      // 3. Auto-expire OTPs
      final hasOtp = updatedItem.extractedFeatures?['otp'] != null ||
          updatedItem.title.toLowerCase().contains('otp') ||
          updatedItem.content.toLowerCase().contains('otp');
      if (hasOtp && ghostResult.reviewScore == 0.0) {
        updatedItem = updatedItem.copyWith(state: ReviewState.EXPIRED);
      }

      // 4. Auto-expire reminders
      final hasDeadline = updatedItem.extractedFeatures?['hasDeadline'] == true ||
          updatedItem.title.toLowerCase().contains('deadline') ||
          updatedItem.content.toLowerCase().contains('deadline') ||
          updatedItem.title.toLowerCase().contains('reminder') ||
          updatedItem.content.toLowerCase().contains('reminder') ||
          RegExp(r'\bin\s+(\d{1,4})\s*(minute|minutes|min|mins|hour|hours|hr|hrs|day|days)\b', caseSensitive: false)
              .hasMatch(updatedItem.content.toLowerCase());
      if (hasDeadline && ghostResult.reviewScore == 0.0) {
        updatedItem = updatedItem.copyWith(state: ReviewState.EXPIRED);
      }

      // 5. Remove completed payment reminders (transition to ARCHIVED)
      final isFinance =
          (updatedItem.classifiedCategory ?? updatedItem.category ?? '').toLowerCase() == 'finance' ||
              updatedItem.extractedFeatures?['amount'] != null ||
              updatedItem.title.toLowerCase().contains('bill') ||
              updatedItem.title.toLowerCase().contains('payment') ||
              updatedItem.title.toLowerCase().contains('finance') ||
              updatedItem.content.toLowerCase().contains('bill') ||
              updatedItem.content.toLowerCase().contains('payment') ||
              updatedItem.content.toLowerCase().contains('finance') ||
              updatedItem.content.toLowerCase().contains('rs');
      final isCompleted = _checkCompletedKeywords(updatedItem.title, updatedItem.content);
      if (isFinance && isCompleted) {
        updatedItem = updatedItem.copyWith(state: ReviewState.ARCHIVED);
      }

      updated.add(updatedItem);

      // Save updated items to DB
      if (_db != null) {
        await DriftNotificationStorage(_db).save(updatedItem);
        await _saveQueueEntry(updatedItem, expiry: updatedItem.snoozedUntil);
      }
    }

    state = updated;
  }

  /// Clears all items in the queue (used for testing).
  void clear() {
    state = [];
    if (_db != null) {
      _db.reviewQueueDao.clearAll();
    }
  }

  Future<void> _saveQueueEntry(AppNotification n, {DateTime? expiry}) async {
    if (_db == null) return;
    await _db.reviewQueueDao.insertItem(ReviewQueueEntry(
      id: 0,
      notificationId: n.id,
      priority: n.priority ?? 'medium',
      enqueueTime: DateTime.now(),
      expiryTime: expiry,
      status: n.state,
    ));
  }

  bool _checkCompletedKeywords(String title, String content) {
    final lowerTitle = title.toLowerCase();
    final lowerContent = content.toLowerCase();
    final completedRegex = RegExp(
      r'\b(completed|done|finished|resolved|successful|delivered|succeeded)\b',
      caseSensitive: false,
    );
    return completedRegex.hasMatch(lowerTitle) || completedRegex.hasMatch(lowerContent);
  }
}

// Global Provider Container for ChangeNotifier integration
ProviderContainer? _globalProviderContainerInstance;
ProviderContainer get providerContainer => _globalProviderContainerInstance ??= ProviderContainer();

// Providers
final reviewQueueProvider = StateNotifierProvider<ReviewQueueNotifier, List<AppNotification>>((ref) {
  final db = ref.watch(databaseProvider);
  return ReviewQueueNotifier(db);
});

final reviewQueueSortOrderProvider = StateProvider<QueueSortOrder>((ref) {
  return QueueSortOrder.reviewScore;
});

final sortedReviewQueueProvider = Provider<List<AppNotification>>((ref) {
  final list = ref.watch(reviewQueueProvider);
  final sortOrder = ref.watch(reviewQueueSortOrderProvider);

  // Filter only active review queue items (ACTIVE or SNOOZED that has already expired)
  final activeItems = list.where((n) {
    if (n.state == ReviewState.ACTIVE) return true;
    if (n.state == ReviewState.SNOOZED) {
      if (n.snoozedUntil != null && DateTime.now().isAfter(n.snoozedUntil!)) {
        return true;
      }
    }
    return false;
  }).toList();

  switch (sortOrder) {
    case QueueSortOrder.reviewScore:
      activeItems.sort((a, b) {
        final scoreA = a.priorityScore ?? 0.0;
        final scoreB = b.priorityScore ?? 0.0;
        return scoreB.compareTo(scoreA); // Descending
      });
      break;
    case QueueSortOrder.deadline:
      activeItems.sort((a, b) {
        final aRemaining = a.extractedFeatures?['deadline_minutes_remaining'] as num? ?? -1;
        final bRemaining = b.extractedFeatures?['deadline_minutes_remaining'] as num? ?? -1;
        
        final aHas = aRemaining >= 0;
        final bHas = bRemaining >= 0;
        
        if (aHas && bHas) {
          return aRemaining.compareTo(bRemaining); // Ascending
        }
        if (aHas) return -1;
        if (bHas) return 1;
        return b.timestamp.compareTo(a.timestamp); // Fallback to timestamp descending
      });
      break;
    case QueueSortOrder.lastUpdated:
      activeItems.sort((a, b) {
        final timeA = a.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(a.timestamp);
        final timeB = b.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(b.timestamp);
        return timeB.compareTo(timeA); // Descending
      });
      break;
  }

  return activeItems;
});
