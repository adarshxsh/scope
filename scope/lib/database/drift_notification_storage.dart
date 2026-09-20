import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/database/attention_database.dart';

class DriftNotificationStorage implements NotificationStorage {
  final AttentionDatabase _db;
  DriftNotificationStorage(this._db);

  @override
  Future<void> save(AppNotification notification) async {
    try {
      final existing = await _db.notificationDao.getById(notification.id);
      await _db.notificationDao.insertNotification(_toEntry(notification, existing));
    } catch (e) {
      if (e.toString().contains('closing') ||
          e.toString().contains('closed') ||
          e.toString().contains('ensureOpen')) return;
      rethrow;
    }
  }

  @override
  Future<void> saveAll(List<AppNotification> notifications) async {
    for (final notification in notifications) {
      await save(notification);
    }
  }

  @override
  Future<List<AppNotification>> getAll() async {
    final entries = await _db.notificationDao.getAll();
    return entries.map(_toModel).toList();
  }

  @override
  Future<AppNotification?> getById(String id) async {
    final entry = await _db.notificationDao.getById(id);
    if (entry == null) return null;
    return _toModel(entry);
  }

  @override
  Future<int> deleteOlderThan(int cutoffTimestamp) async {
    return await _db.notificationDao.deleteOlderThan(cutoffTimestamp);
  }

  @override
  Future<void> clear() async {
    await _db.notificationDao.clearAll();
  }

  @override
  Future<int> get count async {
    return await _db.notificationDao.getCount();
  }

  bool _isRedacted(String text) => text.contains('[REDACTED_');

  NotificationEntry _toEntry(AppNotification n, [NotificationEntry? existing]) {
    String title = n.title;
    String content = n.content;

    if (existing != null) {
      if (_isRedacted(title) && !_isRedacted(existing.title)) {
        title = existing.title;
      }
      if (_isRedacted(content) && !_isRedacted(existing.content)) {
        content = existing.content;
      }
    }

    return NotificationEntry(
      id: n.id,
      packageName: n.packageName,
      title: title,
      content: content,
      timestamp: n.timestamp,
      category: n.category,
      isOngoing: n.isOngoing,
      priority: n.priority,
      priorityScore: n.priorityScore,
      classifiedCategory: n.classifiedCategory,
      explanation: n.explanation,
      latencyMs: n.latencyMs,
      ruleVersion: n.ruleVersion,
      modelVersion: n.modelVersion,
      engineVersion: n.engineVersion,
      extractedFeatures: n.extractedFeatures,
      state: n.state,
      snoozedUntil: n.snoozedUntil,
      lastUpdated: n.lastUpdated,
      reviewed: n.state == ReviewState.REVIEWED,
      dismissed: n.state == ReviewState.ARCHIVED || n.state == ReviewState.EXPIRED,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );
  }

  AppNotification _toModel(NotificationEntry entry) {
    return AppNotification(
      id: entry.id,
      packageName: entry.packageName,
      title: entry.title,
      content: entry.content,
      timestamp: entry.timestamp,
      category: entry.category,
      isOngoing: entry.isOngoing,
      priority: entry.priority,
      priorityScore: entry.priorityScore,
      classifiedCategory: entry.classifiedCategory,
      explanation: entry.explanation,
      latencyMs: entry.latencyMs,
      ruleVersion: entry.ruleVersion,
      modelVersion: entry.modelVersion,
      engineVersion: entry.engineVersion,
      extractedFeatures: entry.extractedFeatures,
      state: entry.state,
      snoozedUntil: entry.snoozedUntil,
      lastUpdated: entry.lastUpdated,
    );
  }
}
