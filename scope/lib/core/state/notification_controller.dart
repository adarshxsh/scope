import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/core/testing/test_notification_generator.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/core/state/providers.dart';
import 'package:scope/database/database_provider.dart';
import 'package:scope/database/drift_notification_storage.dart';

/// Session stats collected during a Focus review.
class ReviewSessionStats {
  int notificationsReviewed = 0;
  int actionsCompleted = 0;
  int calendarEventsCreated = 0;
  int remindersCreated = 0;
  int archived = 0;

  /// Rough estimate: ~45 seconds saved per reviewed notification.
  int get estimatedMinutesSaved => ((notificationsReviewed * 45) / 60).ceil();
}

/// Central state for notifications, user actions, and review sessions.
class NotificationController extends ChangeNotifier {
  NotificationController({
    NotificationBridge? bridge,
    NotificationStorage? storage,
    GhostAnalysisEngine? engine,
    ProviderContainer? container,
  })  : _bridge = bridge ?? NotificationBridge(),
        _container = container ?? providerContainer,
        _storage = storage ?? DriftNotificationStorage(container?.read(databaseProvider) ?? providerContainer.read(databaseProvider)),
        _engine = engine ?? GhostAnalysisEngine() {
    _engine.initialize();

    // Listen to changes in Riverpod's reviewQueueProvider to keep legacy notifier list in sync
    _container.listen<List<AppNotification>>(reviewQueueProvider, (previous, next) {
      _notifications = next;
      notifyListeners();
    });

    // Populate initial notifications from storage, if any
    _loadInitialNotifications();
  }

  final NotificationBridge _bridge;
  final NotificationStorage _storage;
  final GhostAnalysisEngine _engine;
  final ProviderContainer _container;

  List<AppNotification> _notifications = [];
  bool _isListenerEnabled = false;
  bool _isLoading = true;
  Timer? _pollTimer;

  ReviewSessionStats sessionStats = ReviewSessionStats();
  FocusArea? _focusAreaFilter;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  FocusArea? get focusAreaFilter => _focusAreaFilter;
  bool get isListenerEnabled => _isListenerEnabled;
  bool get isLoading => _isLoading;
  GhostAnalysisEngine get engine => _engine;

  List<AppNotification> get activeNotifications =>
      _notifications.where((n) => n.state == ReviewState.ACTIVE).toList();

  List<AppNotification> get needsAction => activeNotifications
      .where((n) => n.priority == 'critical' || n.priority == 'high')
      .toList();

  List<AppNotification> get important => activeNotifications
      .where((n) => n.priority == 'medium' || n.priority == null)
      .toList();

  List<AppNotification> get archivedNotifications =>
      _notifications.where((n) => n.state == ReviewState.ARCHIVED).toList();

  List<AppNotification> get completedToday =>
      _notifications.where((n) => n.state == ReviewState.REVIEWED).toList();

  List<AppNotification> get reviewQueue {
    final queue = _container.read(sortedReviewQueueProvider);
    if (_focusAreaFilter == null) return queue;
    return queue.where((n) => FocusAreaMapper.areaFor(n) == _focusAreaFilter).toList();
  }

  Map<FocusArea, int> get focusAreaCounts => FocusAreaMapper.countsFor(activeNotifications);

  int get actionCountToday => needsAction.length;

  int get deadlineCount => activeNotifications
      .where((n) => n.extractedFeatures?['hasDeadline'] == true)
      .length;

  int get financialUpdateCount => activeNotifications.where((n) {
        final features = n.extractedFeatures;
        return features?['amount'] != null ||
            (n.classifiedCategory ?? n.category ?? '').toLowerCase() == 'finance';
      }).length;

  /// ~30 seconds per notification in a Focus session.
  int get estimatedReviewMinutes {
    final count = reviewQueue.length;
    if (count == 0) return 0;
    return (count * 0.5).ceil().clamp(1, 99);
  }

  List<AppNotification> notificationsForArea(FocusArea area) =>
      activeNotifications.where((n) => FocusAreaMapper.areaFor(n) == area).toList();

  void setFocusAreaFilter(FocusArea? area) {
    _focusAreaFilter = area;
    notifyListeners();
  }

  void clearFocusAreaFilter() => setFocusAreaFilter(null);

  void startPolling() {
    _pollTimer?.cancel();
    _checkPermissionAndFetch();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      fetchNotifications();
      runBackgroundCleanup();
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }

  Future<void> _loadInitialNotifications() async {
    _notifications = await _storage.getAll();
    if (_notifications.isNotEmpty) {
      final notifier = _container.read(reviewQueueProvider.notifier);
      notifier.load(_notifications);
      await notifier.rescore();
    }
  }

  /// Cleans up old notifications (older than 7 days) and orphaned review queue items.
  Future<void> runBackgroundCleanup() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      await _storage.deleteOlderThan(cutoff);

      final db = _container.read(databaseProvider);
      final activeNotifications = await _storage.getAll();
      final activeIds = activeNotifications.map((n) => n.id).toSet();

      final queueEntries = await db.reviewQueueDao.getAll();
      for (final entry in queueEntries) {
        if (!activeIds.contains(entry.notificationId)) {
          await db.reviewQueueDao.deleteItem(entry.notificationId);
        }
      }
    } catch (_) {
      // Silently handle errors to not interrupt UI
    }
  }

  Future<void> _checkPermissionAndFetch() async {
    _isListenerEnabled = await _bridge.isListenerEnabled();
    await fetchNotifications();
  }

  Future<void> refresh() => _checkPermissionAndFetch();

  Future<void> fetchNotifications() async {
    try {
      final newNotifications = await _bridge.getNotifications();
      final analyzed = <AppNotification>[];
      final existing = await _storage.getAll();

      for (final raw in newNotifications) {
        // Find if there is an existing notification with the same package, title, and content
        AppNotification? duplicate;
        for (final n in existing) {
          if (n.packageName == raw.packageName &&
              n.title == raw.title &&
              n.content == raw.content) {
            duplicate = n;
            break;
          }
        }

        if (duplicate != null) {
          // If duplicate exists, preserve its ID to overwrite/upsert it instead of making a redundant row
          final updated = raw.copyWith(id: duplicate.id);
          analyzed.add(await _engine.analyze(updated));
        } else {
          // Ensure we don't insert duplicates within the current incoming batch
          final inBatch = analyzed.any((n) =>
              n.packageName == raw.packageName &&
              n.title == raw.title &&
              n.content == raw.content);
          if (!inBatch) {
            analyzed.add(await _engine.analyze(raw));
          }
        }
      }

      if (analyzed.isNotEmpty) {
        await _storage.saveAll(analyzed);
      }
      final loaded = await _storage.getAll();
      
      final notifier = _container.read(reviewQueueProvider.notifier);
      for (final item in loaded) {
        notifier.add(item);
      }
      await notifier.rescore();

      _isLoading = false;
      notifyListeners();
    } catch (_) {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> generateTestData() async {
    final generator = TestNotificationGenerator();
    final testNotifs = generator.generateAll();
    final analyzed = <AppNotification>[];
    final existing = await _storage.getAll();

    for (final raw in testNotifs) {
      AppNotification? duplicate;
      for (final n in existing) {
        if (n.packageName == raw.packageName &&
            n.title == raw.title &&
            n.content == raw.content) {
          duplicate = n;
          break;
        }
      }

      if (duplicate != null) {
        final updated = raw.copyWith(id: duplicate.id);
        analyzed.add(await _engine.analyze(updated));
      } else {
        final inBatch = analyzed.any((n) =>
            n.packageName == raw.packageName &&
            n.title == raw.title &&
            n.content == raw.content);
        if (!inBatch) {
          analyzed.add(await _engine.analyze(raw));
        }
      }
    }

    await _storage.saveAll(analyzed);
    final loaded = await _storage.getAll();
    
    final notifier = _container.read(reviewQueueProvider.notifier);
    for (final item in loaded) {
      notifier.add(item);
    }
    await notifier.rescore();

    notifyListeners();
  }

  Future<void> clearAll() async {
    await _storage.clear();
    _container.read(reviewQueueProvider.notifier).clear();
    _notifications = [];
    sessionStats = ReviewSessionStats();
    notifyListeners();
  }

  void openNotificationSettings() => _bridge.openNotificationSettings();

  void archive(String id) {
    _container.read(reviewQueueProvider.notifier).archive(id);
    sessionStats.archived++;
    notifyListeners();
  }

  void complete(String id) {
    _container.read(reviewQueueProvider.notifier).reviewed(id);
    sessionStats.actionsCompleted++;
    notifyListeners();
  }

  void snooze(String id, Duration duration) {
    _container.read(reviewQueueProvider.notifier).snooze(id, duration);
    notifyListeners();
  }

  void recordCalendarEvent() {
    sessionStats.calendarEventsCreated++;
    notifyListeners();
  }

  void recordReminder() {
    sessionStats.remindersCreated++;
    notifyListeners();
  }

  void recordReviewed() {
    sessionStats.notificationsReviewed++;
    notifyListeners();
  }

  void recordAction() {
    sessionStats.actionsCompleted++;
    notifyListeners();
  }

  void resetSessionStats() {
    sessionStats = ReviewSessionStats();
    notifyListeners();
  }

  bool isArchived(String id) {
    for (final n in _notifications) {
      if (n.id == id) return n.state == ReviewState.ARCHIVED;
    }
    return false;
  }

  bool isCompleted(String id) {
    for (final n in _notifications) {
      if (n.id == id) return n.state == ReviewState.REVIEWED;
    }
    return false;
  }

  List<AppNotification> search(String query) {
    if (query.trim().isEmpty) return [];
    final q = query.toLowerCase();
    return _notifications.where((n) {
      return n.title.toLowerCase().contains(q) ||
          n.content.toLowerCase().contains(q) ||
          n.packageName.toLowerCase().contains(q);
    }).toList();
  }
}
