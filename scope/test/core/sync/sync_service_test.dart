import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/privacy_budget_manager.dart';
import 'package:scope/core/sync/e2ee_sync_engine.dart';
import 'package:scope/core/sync/sync_service.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AttentionDatabase dbA;
  late AttentionDatabase dbB;
  late E2EESyncEngine encryptor;
  late InMemorySyncTransport transport;
  late SyncService syncServiceA;
  late SyncService syncServiceB;

  setUp(() async {
    dbA = AttentionDatabase.inMemory();
    dbB = AttentionDatabase.inMemory();
    encryptor = E2EESyncEngine.fromPassphrase('shared-zero-knowledge-secret-2026');
    transport = InMemorySyncTransport();

    syncServiceA = SyncService(
      deviceId: 'device-A',
      db: dbA,
      encryptor: encryptor,
      transport: transport,
    );

    syncServiceB = SyncService(
      deviceId: 'device-B',
      db: dbB,
      encryptor: encryptor,
      transport: transport,
    );

    final now = DateTime.now();
    final notif = NotificationEntry(
      id: 'n-100',
      packageName: 'com.example.app',
      title: 'Payment Alert',
      content: 'Your transaction was successful',
      timestamp: 1700000000000,
      state: ReviewState.ACTIVE,
      reviewed: false,
      dismissed: false,
      isOngoing: false,
      createdAt: now,
    );

    await dbA.notificationDao.insertNotification(notif);
    await dbB.notificationDao.insertNotification(notif);
  });

  tearDown(() async {
    syncServiceA.dispose();
    syncServiceB.dispose();
    transport.dispose();
    await dbA.close();
    await dbB.close();
  });

  test('SyncService propagates notification review state from Device A to Device B', () async {
    await syncServiceA.syncNotificationState(
      notificationId: 'n-100',
      state: ReviewState.REVIEWED,
    );

    await Future.delayed(const Duration(milliseconds: 50));

    final updatedInB = await dbB.notificationDao.getById('n-100');
    expect(updatedInB, isNotNull);
    expect(updatedInB!.state, equals(ReviewState.REVIEWED));
  });

  test('SyncService propagates custom RLHF rule from Device A to Device B', () async {
    const rule = NotificationRule(
      id: 'rlhf-rule-99',
      category: 'msg',
      priority: 'high',
      conditions: RuleCondition(
        keywords: ['urgent'],
      ),
    );

    await syncServiceA.syncRlhfRule(rule);

    await Future.delayed(const Duration(milliseconds: 50));

    final rulesInB = await dbB.rlhfRulesDao.getRules();
    expect(rulesInB.length, equals(1));
    expect(rulesInB.first.id, equals('rlhf-rule-99'));
  });

  test('SyncService propagates Privacy Budget consumption across devices', () async {
    final transportTest = InMemorySyncTransport();
    final pbmA = PrivacyBudgetManager(db: dbA, dailyEpsilonCap: 1.0);
    final pbmB = PrivacyBudgetManager(db: dbB, dailyEpsilonCap: 1.0);

    final syncA = SyncService(
      deviceId: 'device-A',
      db: dbA,
      encryptor: encryptor,
      transport: transportTest,
      privacyBudgetManager: pbmA,
    );

    final syncB = SyncService(
      deviceId: 'device-B',
      db: dbB,
      encryptor: encryptor,
      transport: transportTest,
      privacyBudgetManager: pbmB,
    );

    await syncA.syncPrivacyBudget(
      date: '2026-09-16',
      epsilonConsumed: 0.3,
    );

    await Future.delayed(const Duration(milliseconds: 50));

    final statusB = await pbmB.getStatus(DateTime(2026, 9, 16));
    expect(statusB.spentToday, closeTo(0.3, 0.001));

    syncA.dispose();
    syncB.dispose();
    transportTest.dispose();
  });

  test('SyncService queues updates when offline and flushes when reconnected', () async {
    await syncServiceA.setOnline(false);

    await syncServiceA.syncNotificationState(
      notificationId: 'n-100',
      state: ReviewState.ARCHIVED,
    );

    // Device B should NOT have received it yet
    final inBBefore = await dbB.notificationDao.getById('n-100');
    expect(inBBefore!.state, equals(ReviewState.ACTIVE));

    // Reconnect Device A
    await syncServiceA.setOnline(true);
    await Future.delayed(const Duration(milliseconds: 50));

    // Device B should now have received the flushed item
    final inBAfter = await dbB.notificationDao.getById('n-100');
    expect(inBAfter!.state, equals(ReviewState.ARCHIVED));
  });

  test('PrivacyBudgetManager automatically triggers SyncService when executing DP queries', () async {
    final transportTest = InMemorySyncTransport();
    final now = DateTime(2026, 9, 16);
    final pbmA = PrivacyBudgetManager(db: dbA, dailyEpsilonCap: 1.0);
    final pbmB = PrivacyBudgetManager(db: dbB, dailyEpsilonCap: 1.0);

    final syncA = SyncService(
      deviceId: 'device-A',
      db: dbA,
      encryptor: encryptor,
      transport: transportTest,
      privacyBudgetManager: pbmA,
    );

    final syncB = SyncService(
      deviceId: 'device-B',
      db: dbB,
      encryptor: encryptor,
      transport: transportTest,
      privacyBudgetManager: pbmB,
    );

    // Device A executes a DP query
    await pbmA.executeNoisedQuery<int>(
      exactQuery: () async => 50,
      sensitivity: 1.0,
      epsilon: 0.2,
      now: now,
    );

    await Future.delayed(const Duration(milliseconds: 50));

    // Device B should have received the synced budget consumption automatically
    final statusB = await pbmB.getStatus(now);
    expect(statusB.spentToday, closeTo(0.2, 0.001));

    syncA.dispose();
    syncB.dispose();
    transportTest.dispose();
  });

  test('SyncService logs audit entry when processing a tampered sync payload', () async {
    const tamperedPayload = EncryptedSyncPayload(
      ciphertext: 'invalid-ciphertext',
      iv: 'aXZmYWtlMTIzNDU2Nzg5MA==',
      authTag: 'bad-auth-tag',
      senderDeviceId: 'device-X',
      payloadType: 'review_state',
      timestamp: 1700000000000,
      vectorClockJson: '{}',
    );

    await syncServiceA.processIncomingPayload(tamperedPayload);

    expect(syncServiceA.auditLogs.length, equals(1));
    expect(syncServiceA.auditLogs.first, contains('Failed to process payload from device-X'));
  });
}
