import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/core/testing/test_notification_generator.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';

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
  })  : _bridge = bridge ?? NotificationBridge(),
        _storage = storage ?? InMemoryNotificationStorage(),
        _engine = engine ?? GhostAnalysisEngine() {
    _engine.initialize();
  }

  final NotificationBridge _bridge;
  final NotificationStorage _storage;
  final GhostAnalysisEngine _engine;

  List<AppNotification> _notifications = [];
  final Set<String> _archivedIds = {};
  final Set<String> _completedIds = {};
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
      _notifications.where((n) => !_archivedIds.contains(n.id) && !_completedIds.contains(n.id)).toList();

  List<AppNotification> get needsAction => activeNotifications
      .where((n) => n.priority == 'critical' || n.priority == 'high')
      .toList();

  List<AppNotification> get important => activeNotifications
      .where((n) => n.priority == 'medium' || n.priority == null)
      .toList();

  List<AppNotification> get archivedNotifications =>
      _notifications.where((n) => _archivedIds.contains(n.id)).toList();

  List<AppNotification> get completedToday =>
      _notifications.where((n) => _completedIds.contains(n.id)).toList();

  List<AppNotification> get reviewQueue {
    final queue = [...needsAction, ...important.where((n) => !needsAction.contains(n))];
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
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => fetchNotifications());
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

  Future<void> _checkPermissionAndFetch() async {
    _isListenerEnabled = await _bridge.isListenerEnabled();
    await fetchNotifications();
  }

  Future<void> refresh() => _checkPermissionAndFetch();

  Future<void> fetchNotifications() async {
    try {
      final newNotifications = await _bridge.getNotifications();
      final analyzed = <AppNotification>[];
      for (final raw in newNotifications) {
        analyzed.add(await _engine.analyze(raw));
      }
      if (analyzed.isNotEmpty) {
        await _storage.saveAll(analyzed);
      }
      _notifications = await _storage.getAll();
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
    for (final raw in testNotifs) {
      analyzed.add(await _engine.analyze(raw));
    }
    await _storage.saveAll(analyzed);
    _notifications = await _storage.getAll();
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _storage.clear();
    _notifications = [];
    _archivedIds.clear();
    _completedIds.clear();
    notifyListeners();
  }

  void openNotificationSettings() => _bridge.openNotificationSettings();

  void archive(String id) {
    _archivedIds.add(id);
    sessionStats.archived++;
    notifyListeners();
  }

  void complete(String id) {
    _completedIds.add(id);
    sessionStats.actionsCompleted++;
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

  bool isArchived(String id) => _archivedIds.contains(id);
  bool isCompleted(String id) => _completedIds.contains(id);

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
