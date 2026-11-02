import 'dart:async';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/privacy_budget_manager.dart';
import 'package:scope/core/sync/crdt.dart';
import 'package:scope/core/sync/e2ee_sync_engine.dart';
import 'package:scope/database/attention_database.dart';

/// Abstract transport layer for dispatching and receiving encrypted sync payloads across network channels.
abstract class SyncTransport {
  void broadcast(EncryptedSyncPayload payload);
  Stream<EncryptedSyncPayload> get incomingPayloads;
  void dispose();
}

/// In-Memory broadcast transport for testing, unit tests, and multi-device simulation.
class InMemorySyncTransport implements SyncTransport {
  final _controller = StreamController<EncryptedSyncPayload>.broadcast();

  @override
  void broadcast(EncryptedSyncPayload payload) {
    if (!_controller.isClosed) {
      _controller.add(payload);
    }
  }

  @override
  Stream<EncryptedSyncPayload> get incomingPayloads => _controller.stream;

  @override
  void dispose() {
    _controller.close();
  }
}

/// Core sync service orchestrating end-to-end encrypted CRDT state synchronization across endpoints.
class SyncService {
  final String deviceId;
  final AttentionDatabase db;
  final E2EESyncEngine encryptor;
  final SyncTransport transport;
  final RuleEngine? ruleEngine;
  final PrivacyBudgetManager? privacyBudgetManager;

  VectorClock _vectorClock = const VectorClock({});
  bool _isOnline = true;
  StreamSubscription<EncryptedSyncPayload>? _transportSubscription;
  final List<String> _auditLogs = [];

  SyncService({
    required this.deviceId,
    required this.db,
    required this.encryptor,
    required this.transport,
    this.ruleEngine,
    this.privacyBudgetManager,
  }) {
    if (privacyBudgetManager != null) {
      privacyBudgetManager!.onBudgetConsumed = (date, epsilon, delta) {
        syncPrivacyBudget(
          date: date,
          epsilonConsumed: epsilon,
          deltaConsumed: delta,
        );
      };
    }
    _initTransportListener();
  }

  bool get isOnline => _isOnline;
  VectorClock get currentVectorClock => _vectorClock;
  List<String> get auditLogs => List.unmodifiable(_auditLogs);

  void _initTransportListener() {
    _transportSubscription = transport.incomingPayloads.listen((payload) {
      if (payload.senderDeviceId == deviceId) return;
      processIncomingPayload(payload);
    });
  }

  /// Sets online status and triggers automatic synchronization of offline queued items when reconnected.
  Future<void> setOnline(bool online) async {
    _isOnline = online;
    if (_isOnline) {
      await flushOfflineQueue();
    }
  }

  /// Synchronizes notification review state updates across devices.
  Future<void> syncNotificationState({
    required String notificationId,
    required ReviewState state,
    DateTime? snoozedUntil,
  }) async {
    _vectorClock = _vectorClock.increment(deviceId);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;

    final delta = NotificationStateDelta(
      notificationId: notificationId,
      state: state,
      snoozedUntil: snoozedUntil,
      originDeviceId: deviceId,
      vectorClock: _vectorClock,
      timestamp: timestamp,
    );

    await db.notificationDao.mergeNotificationStateDelta(delta);

    final encryptedPayload = encryptor.encryptPayload(
      plaintextJson: delta.toJson(),
      senderDeviceId: deviceId,
      payloadType: 'review_state',
      vectorClockJson: _vectorClock.toJson(),
    );

    if (_isOnline) {
      transport.broadcast(encryptedPayload);
    } else {
      await db.offlineSyncQueueDao.enqueue(
        OfflineSyncQueueTableCompanion.insert(
          payloadType: 'review_state',
          entityId: notificationId,
          encryptedPayloadJson: encryptedPayload.toJson(),
        ),
      );
    }
  }

  /// Synchronizes a new or updated custom RLHF rule across devices.
  Future<void> syncRlhfRule(NotificationRule rule) async {
    _vectorClock = _vectorClock.increment(deviceId);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;

    final delta = RlhfRuleDelta(
      ruleId: rule.id,
      rule: rule,
      isDeleted: false,
      originDeviceId: deviceId,
      vectorClock: _vectorClock,
      timestamp: timestamp,
    );

    await db.rlhfRulesDao.mergeRlhfRuleDelta(delta);
    if (ruleEngine != null) {
      ruleEngine!.addReinforcementRule(rule);
    }

    final encryptedPayload = encryptor.encryptPayload(
      plaintextJson: delta.toJson(),
      senderDeviceId: deviceId,
      payloadType: 'rlhf_rule',
      vectorClockJson: _vectorClock.toJson(),
    );

    if (_isOnline) {
      transport.broadcast(encryptedPayload);
    } else {
      await db.offlineSyncQueueDao.enqueue(
        OfflineSyncQueueTableCompanion.insert(
          payloadType: 'rlhf_rule',
          entityId: rule.id,
          encryptedPayloadJson: encryptedPayload.toJson(),
        ),
      );
    }
  }

  /// Synchronizes a deletion tombstone for a custom RLHF rule.
  Future<void> deleteRlhfRule(String ruleId) async {
    _vectorClock = _vectorClock.increment(deviceId);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;

    final delta = RlhfRuleDelta(
      ruleId: ruleId,
      rule: null,
      isDeleted: true,
      originDeviceId: deviceId,
      vectorClock: _vectorClock,
      timestamp: timestamp,
    );

    await db.rlhfRulesDao.mergeRlhfRuleDelta(delta);

    final encryptedPayload = encryptor.encryptPayload(
      plaintextJson: delta.toJson(),
      senderDeviceId: deviceId,
      payloadType: 'rlhf_rule',
      vectorClockJson: _vectorClock.toJson(),
    );

    if (_isOnline) {
      transport.broadcast(encryptedPayload);
    } else {
      await db.offlineSyncQueueDao.enqueue(
        OfflineSyncQueueTableCompanion.insert(
          payloadType: 'rlhf_rule',
          entityId: ruleId,
          encryptedPayloadJson: encryptedPayload.toJson(),
        ),
      );
    }
  }

  /// Synchronizes differential privacy budget consumption across devices.
  Future<void> syncPrivacyBudget({
    required String date,
    required double epsilonConsumed,
    double deltaConsumed = 0.0,
    int queryCount = 1,
  }) async {
    _vectorClock = _vectorClock.increment(deviceId);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;

    final delta = PrivacyBudgetDelta(
      originDeviceId: deviceId,
      date: date,
      epsilonConsumed: epsilonConsumed,
      deltaConsumed: deltaConsumed,
      queryCount: queryCount,
      vectorClock: _vectorClock,
      timestamp: timestamp,
    );

    final encryptedPayload = encryptor.encryptPayload(
      plaintextJson: delta.toJson(),
      senderDeviceId: deviceId,
      payloadType: 'privacy_budget',
      vectorClockJson: _vectorClock.toJson(),
    );

    if (_isOnline) {
      transport.broadcast(encryptedPayload);
    } else {
      await db.offlineSyncQueueDao.enqueue(
        OfflineSyncQueueTableCompanion.insert(
          payloadType: 'privacy_budget',
          entityId: '$date-$timestamp',
          encryptedPayloadJson: encryptedPayload.toJson(),
        ),
      );
    }
  }

  /// Processes an incoming encrypted sync payload from the network.
  Future<void> processIncomingPayload(EncryptedSyncPayload payload) async {
    try {
      final plaintextJson = encryptor.decryptPayload(payload);

      if (payload.payloadType == 'review_state') {
        final delta = NotificationStateDelta.fromJson(plaintextJson);
        await db.notificationDao.mergeNotificationStateDelta(delta);
        _vectorClock = _vectorClock.merge(delta.vectorClock);
      } else if (payload.payloadType == 'rlhf_rule') {
        final delta = RlhfRuleDelta.fromJson(plaintextJson);
        await db.rlhfRulesDao.mergeRlhfRuleDelta(delta);
        _vectorClock = _vectorClock.merge(delta.vectorClock);

        if (ruleEngine != null && delta.rule != null && !delta.isDeleted) {
          ruleEngine!.addReinforcementRule(delta.rule!);
        }
      } else if (payload.payloadType == 'privacy_budget') {
        final delta = PrivacyBudgetDelta.fromJson(plaintextJson);
        if (privacyBudgetManager != null) {
          await privacyBudgetManager!.recordRemoteConsumption(
            date: delta.date,
            epsilon: delta.epsilonConsumed,
            delta: delta.deltaConsumed,
          );
        } else {
          await db.privacyLedgerDao.recordRemoteConsumption(
            delta.date,
            delta.epsilonConsumed,
            delta.deltaConsumed,
          );
        }
        _vectorClock = _vectorClock.merge(delta.vectorClock);
      }
    } catch (e) {
      // Graceful error recovery: log error without breaking execution or exposing cleartext PII
      _auditLogs.add('[SyncService] Failed to process payload from ${payload.senderDeviceId}: ${e.runtimeType}');
    }
  }

  /// Flushes queued offline state changes automatically upon network reconnection.
  Future<void> flushOfflineQueue() async {
    final pending = await db.offlineSyncQueueDao.getPendingItems();
    for (final item in pending) {
      final payload = EncryptedSyncPayload.fromJson(item.encryptedPayloadJson);
      transport.broadcast(payload);
      await db.offlineSyncQueueDao.markSynced(item.id);
    }
  }

  void dispose() {
    _transportSubscription?.cancel();
  }
}
