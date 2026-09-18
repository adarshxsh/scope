import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/privacy_engine.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/core/testing/test_notification_generator.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/core/utils/smart_actions.dart';
import 'package:scope/core/state/providers.dart';
import 'package:drift/drift.dart';
import 'package:scope/database/attention_database.dart';
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
enum FocusFilterType {
  none,
  needsAction,
  important,
  archived,
  focusArea,
}

/// Central state for notifications, user actions, and review sessions.
class NotificationController extends ChangeNotifier {
  NotificationController({
    NotificationBridge? bridge,
    NotificationStorage? storage,
    GhostAnalysisEngine? engine,
    PrivacyEngine? privacyEngine,
    ProviderContainer? container,
  })  : _bridge = bridge ?? NotificationBridge(),
        _container = container ?? providerContainer,
        _storage = storage ?? DriftNotificationStorage(container?.read(databaseProvider) ?? providerContainer.read(databaseProvider)),
        _engine = engine ?? GhostAnalysisEngine(),
        _privacyEngine = privacyEngine ?? PrivacyEngine() {
    _engine.initialize();

    // Listen to changes in Riverpod's reviewQueueProvider to keep legacy notifier list in sync
    _container.listen<List<AppNotification>>(reviewQueueProvider, (previous, next) {
      _notifications = next;
      notifyListeners();
    });

    // Sync initial native privacy rules
    _syncPrivacyRulesFromNative();

    // Populate initial notifications from storage, if any
    _loadInitialNotifications();
  }

  final NotificationBridge _bridge;
  final NotificationStorage _storage;
  final GhostAnalysisEngine _engine;
  final PrivacyEngine _privacyEngine;
  final ProviderContainer _container;

  List<AppNotification> _notifications = [];
  bool _isListenerEnabled = false;
  bool _isLoading = true;
  Timer? _pollTimer;
  Timer? _cleanupTimer;
  bool _isCleaningUp = false;

  ReviewSessionStats sessionStats = ReviewSessionStats();

  FocusFilterType _filterType = FocusFilterType.none;
  FocusArea? _focusAreaFilter;
  bool _initialLoadCompleted = false;

  // Focus Session state
  bool _inFocusSession = false;
  List<String> _focusSessionQueueIds = [];
  DateTime? _focusSessionStart;
  int _focusSessionInterruptions = 0;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  /// Notifications excluding app promotional cards (used for stats/counts only).
  List<AppNotification> _countable(List<AppNotification> list) =>
      list.where((n) => !TestNotificationGenerator.isAppPromo(n)).toList();
  FocusFilterType get filterType => _filterType;
  FocusArea? get focusAreaFilter => _focusAreaFilter;
  bool get isListenerEnabled => _isListenerEnabled;
  bool get isLoading => _isLoading;
  GhostAnalysisEngine get engine => _engine;

  bool get inFocusSession => _inFocusSession;
  List<String> get focusSessionQueueIds => List.unmodifiable(_focusSessionQueueIds);
  DateTime? get focusSessionStart => _focusSessionStart;
  int get focusSessionInterruptions => _focusSessionInterruptions;

  List<AppNotification> get activeNotifications =>
      _notifications.where((n) => n.state == ReviewState.ACTIVE).toList();

  /// Active notifications excluding app promotional cards (for stat counting).
  List<AppNotification> get _countableActive => _countable(activeNotifications);

  List<AppNotification> get needsAction => _countableActive
      .where((n) => n.priority == 'critical' || n.priority == 'high')
      .toList();

  List<AppNotification> get important => _countableActive
      .where((n) => n.priority == 'medium' || n.priority == null)
      .toList();

  List<AppNotification> get archivedNotifications =>
      _countable(_notifications.where((n) => n.state == ReviewState.ARCHIVED).toList());

  List<AppNotification> get completedToday =>
      _countable(_notifications.where((n) => n.state == ReviewState.REVIEWED).toList());

  /// Total notifications excluding app promotional cards (for display counts).
  int get countableTotal => _countable(_notifications).length;

  List<AppNotification> get reviewQueue {
    final queue = _container.read(sortedReviewQueueProvider);
    
    switch (_filterType) {
      case FocusFilterType.none:
        return queue;
      case FocusFilterType.needsAction:
        return queue
            .where((n) => n.priority == 'critical' || n.priority == 'high')
            .toList();
      case FocusFilterType.important:
        return queue
            .where((n) => n.priority == 'medium' || n.priority == null)
            .toList();
      case FocusFilterType.archived:
        return archivedNotifications;
      case FocusFilterType.focusArea:
        if (_focusAreaFilter == null) return queue;
        return queue
            .where((n) => FocusAreaMapper.areaFor(n) == _focusAreaFilter)
            .toList();
    }
  }

  Map<FocusArea, int> get focusAreaCounts => FocusAreaMapper.countsFor(_countableActive);

  int get actionCountToday => needsAction.length;

  int get deadlineCount => _countableActive
      .where((n) => n.extractedFeatures?['hasDeadline'] == true)
      .length;

  int get financialUpdateCount => _countableActive.where((n) {
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

  void setFilter(FocusFilterType type, [FocusArea? area]) {
    _filterType = type;
    _focusAreaFilter = area;
    notifyListeners();
  }

  void clearFilter() {
    _filterType = FocusFilterType.none;
    _focusAreaFilter = null;
    notifyListeners();
  }

  void setFocusAreaFilter(FocusArea? area) {
    if (area == null) {
      clearFilter();
    } else {
      setFilter(FocusFilterType.focusArea, area);
    }
  }

  void clearFocusAreaFilter() => clearFilter();

  void startFocusSession() {
    _inFocusSession = true;
    _focusSessionQueueIds = reviewQueue.map((n) => n.id).toList();
    _focusSessionStart = DateTime.now();
    _focusSessionInterruptions = 0;
    resetSessionStats();

    final db = _container.read(databaseProvider);
    db.focusSessionDao.insertSession(FocusSessionEntry(
      id: 0,
      sessionStart: _focusSessionStart!,
      interruptions: 0,
      completion: false,
      duration: 0,
    ));

    notifyListeners();
  }

  void skipFocusSessionItem(String id) {
    if (_focusSessionQueueIds.contains(id)) {
      _focusSessionQueueIds.remove(id);
      _focusSessionQueueIds.add(id);
      notifyListeners();
    }
  }

  void finishFocusSession() {
    _inFocusSession = false;
    final now = DateTime.now();
    final durationSeconds = _focusSessionStart != null
        ? now.difference(_focusSessionStart!).inSeconds
        : 0;

    final db = _container.read(databaseProvider);
    db.focusSessionDao.getActiveSession().then((active) {
      if (active != null) {
        db.focusSessionDao.updateSession(active.copyWith(
          sessionEnd: Value(now),
          completion: true,
          duration: durationSeconds,
          interruptions: _focusSessionInterruptions,
        ));
      }
    });

    _focusSessionQueueIds.clear();
    clearFilter();
    notifyListeners();
  }

  void recordFocusInterruption() {
    if (_inFocusSession) {
      _focusSessionInterruptions++;
      notifyListeners();
    }
  }

  // Action Items State
  final List<SavedActionItem> _savedActionItems = [];
  List<SavedActionItem> get savedActionItems => List.unmodifiable(_savedActionItems);

  void saveActionItem(AppNotification notification, SmartAction action) {
    // Add to saved items
    _savedActionItems.add(SavedActionItem(notification: notification, action: action));
    
    // Archive it so it leaves the review queue
    archive(notification.id);
  }

  void removeSavedActionItem(SavedActionItem item) {
    _savedActionItems.remove(item);
    notifyListeners();
  }

  int get focusSessionProgressCount {
    int count = 0;
    for (final id in _focusSessionQueueIds) {
      final isStillActive = reviewQueue.any((n) => n.id == id);
      if (!isStillActive) {
        count++;
      }
    }
    return count;
  }

  AppNotification? get currentFocusNotification {
    for (final id in _focusSessionQueueIds) {
      final index = reviewQueue.indexWhere((n) => n.id == id);
      if (index >= 0) {
        return reviewQueue[index];
      }
    }
    return null;
  }

  void startPolling() {
    _pollTimer?.cancel();
    _checkPermissionAndFetch();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      fetchNotifications();
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    stopPolling();
    _cleanupTimer?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  Future<void> _loadInitialNotifications() async {
    if (_initialLoadCompleted) return;
    final loaded = await _storage.getAll();
    if (_initialLoadCompleted) return;

    if (_notifications.isEmpty) {
      _notifications = loaded;
    }
    if (_notifications.isNotEmpty) {
      final notifier = _container.read(reviewQueueProvider.notifier);
      notifier.load(_notifications);
      await notifier.rescore();
    }
    _initialLoadCompleted = true;
    _isLoading = false;
    notifyListeners();

    // Trigger initial cleanup once on startup
    runBackgroundCleanup();
    
    // Set up daily cleanup timer
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(hours: 24), (_) {
      runBackgroundCleanup();
    });
  }

  /// Cleans up old notifications (older than 7 days) and orphaned review queue items.
  Future<void> runBackgroundCleanup() async {
    if (_isCleaningUp) return;

    try {
      _isCleaningUp = true;
      
      // Defer execution if user is engaged in active focus session interactions
      while (_inFocusSession) {
        await Future.delayed(const Duration(minutes: 5));
        if (_isDisposed) return;
      }

      final cutoff = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      final db = _container.read(databaseProvider);
      
      // Execute the single-step atomic transaction
      await db.runSetBasedCleanup(cutoff);

    } catch (_) {
      // Silently handle errors to not interrupt UI
    } finally {
      _isCleaningUp = false;
    }
  }

  Future<void> _checkPermissionAndFetch() async {
    _isListenerEnabled = await _bridge.isListenerEnabled();
    await fetchNotifications();
  }

  Future<void> refresh() => _checkPermissionAndFetch();

  Future<void> _syncPrivacyRulesFromNative() async {
    try {
      final blacklisted = await _bridge.getPackageExclusionList();
      if (blacklisted.isNotEmpty) {
        _privacyEngine.setBlacklistedPackages(blacklisted);
      }
      final categories = await _bridge.getCategoryExclusionRules();
      if (categories.isNotEmpty) {
        _privacyEngine.setExcludedCategories(categories);
      }
    } catch (_) {
      // Ignore bridge errors on non-Android or uninitialized platforms
    }
  }

  PrivacyEngine get privacyEngine => _privacyEngine;

  bool isPackageBlacklisted(String packageName) =>
      _privacyEngine.isPackageBlacklisted(packageName);

  Future<void> togglePackageBlacklist(
      String packageName, bool enableIngestion) async {
    if (enableIngestion) {
      _privacyEngine.removeBlacklistedPackage(packageName);
    } else {
      _privacyEngine.addBlacklistedPackage(packageName);
    }
    await _bridge
        .setPackageExclusionList(_privacyEngine.blacklistedPackages.toList());
    notifyListeners();
  }

  Future<void> setSensitiveCategoryExclusion({
    bool? excludeOtpAndHealth,
    bool? excludeFinance,
  }) async {
    _privacyEngine.setSensitiveCategoryRules(
      excludeOtpAndHealth: excludeOtpAndHealth,
      excludeFinance: excludeFinance,
    );
    await _bridge
        .setCategoryExclusionRules(_privacyEngine.effectiveCategoryRules);
    notifyListeners();
  }

  void toggleFieldSanitization(bool enabled) {
    _privacyEngine.setFieldSanitization(enabled);
    notifyListeners();
  }

  Future<List<Map<String, String>>> getInstalledApps() async {
    final nativeApps = await _bridge.getInstalledApps();
    if (nativeApps.isNotEmpty) {
      return nativeApps;
    }

    // Fallback/Demo list of installed apps for testing/non-Android
    final Map<String, String> knownMap = {
      'com.google.android.calendar': 'Google Calendar',
      'com.google.android.gm': 'Gmail',
      'org.telegram.messenger': 'Telegram',
      'com.whatsapp': 'WhatsApp',
      'com.signal.app': 'Signal',
      'com.phonepe.app': 'PhonePe',
      'com.nextbillion.groww': 'Groww',
      'com.myairtelapp': 'Airtel Thanks',
      'net.one97.paytm': 'Paytm',
      'in.amazon.mShop.android.shopping': 'Amazon',
      'com.application.zomato': 'Zomato',
      'com.spotify.music': 'Spotify',
      'com.zerodha.kite3': 'Zerodha Kite',
      'com.myntra.android': 'Myntra',
      'com.jio.myjio': 'MyJio',
      'com.atlassian.android.jira.core': 'Jira',
      'com.google.android.apps.docs': 'Google Drive',
    };

    for (final n in _notifications) {
      if (!knownMap.containsKey(n.packageName)) {
        knownMap[n.packageName] = n.packageName.split('.').last;
      }
    }

    final list = knownMap.entries
        .map((e) => {'appName': e.value, 'packageName': e.key})
        .toList();
    list.sort((a, b) =>
        a['appName']!.toLowerCase().compareTo(b['appName']!.toLowerCase()));
    return list;
  }

  Future<void> fetchNotifications() async {
    try {
      final newNotifications = await _bridge.getNotifications();
      final analyzed = <AppNotification>[];

      if (!_initialLoadCompleted) {
        await _loadInitialNotifications();
      }

      for (final raw in newNotifications) {
        // Ignore ongoing background/system notifications (e.g. charging, media playback)
        if (raw.isOngoing) continue;

        // Dart Pre-Storage Privacy Gate: Drop blacklisted packages or excluded sensitive categories
        if (_privacyEngine.shouldDrop(raw)) {
          continue;
        }

        // Apply optional field sanitization prior to processing
        final processedRaw = _privacyEngine.sanitize(raw);

        final isDuplicate = _notifications.any((n) =>
            n.packageName == processedRaw.packageName &&
            n.timestamp == processedRaw.timestamp &&
            n.title == processedRaw.title &&
            n.content == processedRaw.content);

        if (!isDuplicate) {
          final inBatch = analyzed.any((n) =>
              n.packageName == processedRaw.packageName &&
              n.timestamp == processedRaw.timestamp &&
              n.title == processedRaw.title &&
              n.content == processedRaw.content);
          if (!inBatch) {
            analyzed.add(await _engine.analyze(processedRaw));
          }
        }
      }

      if (analyzed.isNotEmpty) {
        await _storage.saveAll(analyzed);
        final loaded = await _storage.getAll();
        final notifier = _container.read(reviewQueueProvider.notifier);
        notifier.load(loaded);
        await notifier.rescore();
      }

      _isLoading = false;
      notifyListeners();
    } catch (_) {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> generateTestData() async {
    _initialLoadCompleted = true;
    _isLoading = false;
    final generator = TestNotificationGenerator();
    final testNotifs = generator.generateAll();
    final analyzed = <AppNotification>[];

    for (final raw in testNotifs) {
      // Dart Pre-Storage Privacy Gate
      if (_privacyEngine.shouldDrop(raw)) {
        continue;
      }

      final processedRaw = _privacyEngine.sanitize(raw);

      final isDuplicate = _notifications.any((n) =>
          n.packageName == processedRaw.packageName &&
          n.timestamp == processedRaw.timestamp &&
          n.title == processedRaw.title &&
          n.content == processedRaw.content);

      if (!isDuplicate) {
        final inBatch = analyzed.any((n) =>
            n.packageName == processedRaw.packageName &&
            n.timestamp == processedRaw.timestamp &&
            n.title == processedRaw.title &&
            n.content == processedRaw.content);
        if (!inBatch) {
          analyzed.add(await _engine.analyze(processedRaw));
        }
      }
    }

    if (analyzed.isNotEmpty) {
      await _storage.saveAll(analyzed);
      final loaded = await _storage.getAll();
      final notifier = _container.read(reviewQueueProvider.notifier);
      notifier.load(loaded);
      await notifier.rescore();
    }

    notifyListeners();
  }

  Future<void> clearAll() async {
    await _storage.clear();
    _container.read(reviewQueueProvider.notifier).clear();
    _notifications = [];
    sessionStats = ReviewSessionStats();
    _focusSessionQueueIds.clear();
    clearFilter();
    notifyListeners();
  }

  void openNotificationSettings() => _bridge.openNotificationSettings();

  void archive(String id) {
    _container.read(reviewQueueProvider.notifier).archive(id);
    _savedActionItems.removeWhere((item) => item.notification.id == id);
    sessionStats.archived++;
    notifyListeners();
  }

  void complete(String id) {
    _container.read(reviewQueueProvider.notifier).reviewed(id);
    _savedActionItems.removeWhere((item) => item.notification.id == id);
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
    List<AppNotification> targetList;
    switch (_filterType) {
      case FocusFilterType.needsAction:
        targetList = needsAction;
        break;
      case FocusFilterType.important:
        targetList = important;
        break;
      case FocusFilterType.archived:
        targetList = archivedNotifications;
        break;
      case FocusFilterType.focusArea:
        if (_focusAreaFilter != null) {
          targetList = notificationsForArea(_focusAreaFilter!);
        } else {
          targetList = _notifications;
        }
        break;
      default:
        targetList = _notifications;
    }

    if (query.trim().isEmpty) {
      return targetList.take(50).toList();
    }
    
    final q = query.toLowerCase();
    return targetList.where((n) {
      return n.title.toLowerCase().contains(q) ||
          n.content.toLowerCase().contains(q) ||
          n.packageName.toLowerCase().contains(q) ||
          (n.classifiedCategory?.toLowerCase().contains(q) ?? false);
    }).toList();
  }
}
