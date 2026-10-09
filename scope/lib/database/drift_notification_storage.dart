import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/database/attention_database.dart';

class DriftNotificationStorage implements NotificationStorage {
  final AttentionDatabase _db;

  DriftNotificationStorage(this._db, {int? maxCapacity}) {
    if (maxCapacity != null) {
      _db.notificationDao.maxCapacity = maxCapacity;
    }
  }

  @override
  int get maxCapacity => _db.notificationDao.maxCapacity;

  @override
  set maxCapacity(int capacity) {
    _db.notificationDao.maxCapacity = capacity;
  }

  @override
  Future<void> save(AppNotification notification) async {
    try {
      await _db.notificationDao.insertNotification(_toEntry(notification));
    } catch (_) {
      // Absorb isolated exception during storage save
    }
  }

  @override
  Future<void> saveAll(List<AppNotification> notifications) async {
    final entries = notifications.map(_toEntry).toList();
    try {
      await _db.notificationDao.insertAll(entries);
    } catch (_) {
      // Absorb isolated exception during batch save
    }
  }

  @override
  Future<List<AppNotification>> getAll() async {
    try {
      final entries = await _db.notificationDao.getAll();
      return entries.map(_toModel).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<AppNotification?> getById(String id) async {
    try {
      final entry = await _db.notificationDao.getById(id);
      if (entry == null) return null;
      return _toModel(entry);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> deleteOlderThan(int cutoffTimestamp) async {
    try {
      return await _db.notificationDao.deleteOlderThan(cutoffTimestamp);
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _db.notificationDao.clearAll();
    } catch (_) {
      // Absorb isolated exception during clear
    }
  }

  @override
  Future<int> get count async {
    try {
      return await _db.notificationDao.getCount();
    } catch (_) {
      return 0;
    }
  }

  NotificationEntry _toEntry(AppNotification n) {
    // Input verification boundaries & length caps
    final id = n.id.trim().isEmpty ? DateTime.now().millisecondsSinceEpoch.toString() : n.id.trim();
    final title = n.title.length > 1000 ? n.title.substring(0, 1000) : n.title;
    final content = n.content.length > 10000 ? n.content.substring(0, 10000) : n.content;
    final timestamp = n.timestamp <= 0 ? DateTime.now().millisecondsSinceEpoch : n.timestamp;

    return NotificationEntry(
      id: id,
      packageName: n.packageName,
      title: title,
      content: content,
      timestamp: timestamp,
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
      createdAt: DateTime.now(),
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
