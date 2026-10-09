/// Notification storage abstraction and in-memory implementation.
///
/// The abstract [NotificationStorage] interface lets us swap backends
/// (in-memory → SQLite → Drift) without changing any consumer code.
library;

import 'package:scope/core/models/notification_model.dart';

/// Abstract interface for notification persistence.
///
/// All methods are async to support future database implementations.
abstract class NotificationStorage {
  /// Save a notification. Overwrites if [notification.id] already exists.
  Future<void> save(AppNotification notification);

  /// Save multiple notifications in a batch.
  Future<void> saveAll(List<AppNotification> notifications);

  /// Retrieve all stored notifications, ordered by timestamp descending
  /// (newest first).
  Future<List<AppNotification>> getAll();

  /// Retrieve a single notification by its ID. Returns null if not found.
  Future<AppNotification?> getById(String id);

  /// Delete all notifications older than [cutoff] timestamp (milliseconds).
  /// Returns the number of deleted notifications.
  Future<int> deleteOlderThan(int cutoffTimestamp);

  /// Delete all stored notifications.
  Future<void> clear();

  /// Returns the current count of stored notifications.
  Future<int> get count;

  /// Gets the maximum row capacity limit (default: 5000).
  int get maxCapacity => 5000;

  /// Sets the maximum row capacity limit.
  set maxCapacity(int capacity) {}
}

/// In-memory implementation of [NotificationStorage].
///
/// Suitable for Phase 1 development and testing.
/// Data is lost when the app restarts — this is intentional.
/// Will be replaced by a persistent backend in a later phase.
class InMemoryNotificationStorage implements NotificationStorage {
  final List<AppNotification> _store = [];
  int _maxCapacity;

  InMemoryNotificationStorage({int maxCapacity = 5000}) : _maxCapacity = maxCapacity;

  @override
  int get maxCapacity => _maxCapacity;

  @override
  set maxCapacity(int capacity) {
    _maxCapacity = capacity;
    _pruneToCapacity();
  }

  @override
  Future<void> save(AppNotification notification) async {
    // Remove existing entry with the same ID (upsert behavior)
    _store.removeWhere((n) => n.id == notification.id);
    _store.add(notification);
    _pruneToCapacity();
  }

  @override
  Future<void> saveAll(List<AppNotification> notifications) async {
    for (final notification in notifications) {
      _store.removeWhere((n) => n.id == notification.id);
      _store.add(notification);
    }
    _pruneToCapacity();
  }

  void _pruneToCapacity() {
    if (_maxCapacity <= 0) return;
    if (_store.length > _maxCapacity) {
      final excess = _store.length - _maxCapacity;
      // Sort candidates for deletion: non-active first, then oldest timestamp first.
      _store.sort((a, b) {
        final aActive = a.state == ReviewState.ACTIVE ? 1 : 0;
        final bActive = b.state == ReviewState.ACTIVE ? 1 : 0;
        if (aActive != bActive) {
          return aActive.compareTo(bActive);
        }
        return a.timestamp.compareTo(b.timestamp);
      });
      _store.removeRange(0, excess);
    }
  }

  @override
  Future<List<AppNotification>> getAll() async {
    // Return a copy sorted by timestamp descending (newest first)
    final sorted = List<AppNotification>.from(_store)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted;
  }

  @override
  Future<AppNotification?> getById(String id) async {
    try {
      return _store.firstWhere((n) => n.id == id);
    } on StateError {
      return null;
    }
  }

  @override
  Future<int> deleteOlderThan(int cutoffTimestamp) async {
    final before = _store.length;
    _store.removeWhere((n) => n.timestamp < cutoffTimestamp);
    return before - _store.length;
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }

  @override
  Future<int> get count async => _store.length;
}
