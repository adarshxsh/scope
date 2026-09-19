import 'package:drift/drift.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/database/attention_database.dart';

class DriftNotificationStorage implements NotificationStorage {
  static const int maxStorageItems = 500;
  final AttentionDatabase _db;

  DriftNotificationStorage(this._db);

  @override
  Future<void> save(AppNotification notification) async {
    final sanitized = _sanitizeAndValidate(notification);
    await _db.notificationDao.insertNotification(_toEntry(sanitized));
    await _enforceCapacityGuardrails();
  }

  @override
  Future<void> saveAll(List<AppNotification> notifications) async {
    final sanitized = notifications.map(_sanitizeAndValidate).toList();
    final entries = sanitized.map(_toEntry).toList();
    await _db.notificationDao.insertAll(entries);
    await _enforceCapacityGuardrails();
  }

  @override
  Future<List<AppNotification>> getAll() async {
    final entries = await _db.notificationDao.getAll();
    return entries.map(_toModel).toList();
  }

  @override
  Future<AppNotification?> getById(String id) async {
    if (id.trim().isEmpty) return null;
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

  /// Sanitizes input boundaries and validates critical notification fields
  AppNotification _sanitizeAndValidate(AppNotification n) {
    final cleanId = _sanitizeString(n.id, maxLength: 128, fallback: 'notif_${DateTime.now().microsecondsSinceEpoch}');
    final cleanPkg = _sanitizeString(n.packageName, maxLength: 128, fallback: 'unknown.package');
    final cleanTitle = _sanitizeString(n.title, maxLength: 1000, fallback: 'No Title');
    final cleanContent = _sanitizeString(n.content, maxLength: 5000, fallback: '');
    final validTimestamp = n.timestamp > 0 ? n.timestamp : DateTime.now().millisecondsSinceEpoch;

    return n.copyWith(
      id: cleanId,
      packageName: cleanPkg,
      title: cleanTitle,
      content: cleanContent,
      timestamp: validTimestamp,
    );
  }

  /// Helper to sanitize text fields, strip null/control bytes, and enforce length bounds
  String _sanitizeString(String? input, {required int maxLength, String fallback = ''}) {
    if (input == null || input.trim().isEmpty) return fallback;
    var clean = input.replaceAll('\x00', '').replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    clean = clean.trim();
    if (clean.length > maxLength) {
      clean = clean.substring(0, maxLength);
    }
    return clean.isEmpty ? fallback : clean;
  }

  /// Bounded memory/storage capacity guardrail (caps database items at 500 max)
  Future<void> _enforceCapacityGuardrails() async {
    try {
      final currentCount = await count;
      if (currentCount > maxStorageItems) {
        final overflow = currentCount - maxStorageItems;
        final oldestEntries = await (_db.select(_db.notificationsTable)
          ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.asc)])
          ..limit(overflow))
          .get();
        if (oldestEntries.isNotEmpty) {
          final idsToDelete = oldestEntries.map((e) => e.id).toList();
          await (_db.delete(_db.notificationsTable)..where((t) => t.id.isIn(idsToDelete))).go();
        }
      }
    } catch (_) {
      // Non-blocking guardrail protection
    }
  }

  NotificationEntry _toEntry(AppNotification n) {
    return NotificationEntry(
      id: n.id,
      packageName: n.packageName,
      title: n.title,
      content: n.content,
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

