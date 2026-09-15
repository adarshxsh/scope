import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/sync/e2ee_sync_engine.dart';
import 'package:scope/core/sync/sync_service.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AttentionDatabase dbA;
  late AttentionDatabase dbB;
  late E2EESyncEngine encryptorA;
  late E2EESyncEngine encryptorB;
  late InMemorySyncTransport sharedTransport;
  late SyncService syncServiceA;
  late SyncService syncServiceB;
  late RuleEngine ruleEngineA;
  late RuleEngine ruleEngineB;

  const passphrase = 'shared-secret-passphrase-2026';

  setUp(() async {
    dbA = AttentionDatabase.inMemory();
    dbB = AttentionDatabase.inMemory();

    encryptorA = E2EESyncEngine.fromPassphrase(passphrase);
    encryptorB = E2EESyncEngine.fromPassphrase(passphrase);

    sharedTransport = InMemorySyncTransport();
    ruleEngineA = RuleEngine();
    ruleEngineB = RuleEngine();

    syncServiceA = SyncService(
      deviceId: 'phone_A',
      db: dbA,
      encryptor: encryptorA,
      transport: sharedTransport,
      ruleEngine: ruleEngineA,
    );

    syncServiceB = SyncService(
      deviceId: 'tablet_B',
      db: dbB,
      encryptor: encryptorB,
      transport: sharedTransport,
      ruleEngine: ruleEngineB,
    );
  });

  tearDown(() async {
    syncServiceA.dispose();
    syncServiceB.dispose();
    sharedTransport.dispose();
    await dbA.close();
    await dbB.close();
  });

  test('Multi-device notification review state sync convergence', () async {
    // Insert initial active notification on device A and device B
    const notifId = 'notif_feed_100';
    final now = DateTime.now();
    final entry = NotificationEntry(
      id: notifId,
      packageName: 'com.whatsapp',
      title: 'Work Group',
      content: 'Team meeting in 5 mins',
      timestamp: now.millisecondsSinceEpoch,
      isOngoing: false,
      state: ReviewState.ACTIVE,
      reviewed: false,
      dismissed: false,
      createdAt: now,
    );
    await dbA.notificationDao.insertNotification(entry);
    await dbB.notificationDao.insertNotification(entry);

    // Device A reviews the notification
    await syncServiceA.syncNotificationState(
      notificationId: notifId,
      state: ReviewState.REVIEWED,
    );

    // Allow async transport event processing
    await Future.delayed(const Duration(milliseconds: 100));

    // Verify device B database converged to REVIEWED
    final notifB = await dbB.notificationDao.getById(notifId);
    expect(notifB, isNotNull);
    expect(notifB!.state, equals(ReviewState.REVIEWED));
    expect(notifB.originDeviceId, equals('phone_A'));
  });

  test('Multi-device custom RLHF rule synchronization', () async {
    const rule = NotificationRule(
      id: 'rlhf-work-chat',
      category: 'msg',
      priority: 'high',
      conditions: RuleCondition(packages: ['com.work.chat'], keywords: ['urgent']),
    );

    // Device A creates RLHF rule
    await syncServiceA.syncRlhfRule(rule);
    await Future.delayed(const Duration(milliseconds: 100));

    // Verify Device B database has rule stored
    final ruleB = await dbB.rlhfRulesDao.getRuleById('rlhf-work-chat');
    expect(ruleB, isNotNull);
    expect(ruleB!.category, equals('msg'));
    expect(ruleB.priority, equals('high'));
    expect(ruleB.isDeleted, isFalse);
  });

  test('Offline queuing and automatic sync upon network reconnection', () async {
    const notifId = 'notif_offline_1';
    final now = DateTime.now();
    final entry = NotificationEntry(
      id: notifId,
      packageName: 'com.slack',
      title: 'Manager',
      content: 'Please review doc',
      timestamp: now.millisecondsSinceEpoch,
      isOngoing: false,
      state: ReviewState.ACTIVE,
      reviewed: false,
      dismissed: false,
      createdAt: now,
    );
    await dbA.notificationDao.insertNotification(entry);
    await dbB.notificationDao.insertNotification(entry);

    // Device A goes offline
    await syncServiceA.setOnline(false);

    final snoozeTime = DateTime.now().toUtc().add(const Duration(hours: 2));
    await syncServiceA.syncNotificationState(
      notificationId: notifId,
      state: ReviewState.SNOOZED,
      snoozedUntil: snoozeTime,
    );

    // Verify item queued offline in Device A queue table
    final pendingA = await dbA.offlineSyncQueueDao.getPendingItems();
    expect(pendingA.length, equals(1));

    // Device B should not have received state yet
    var notifB = await dbB.notificationDao.getById(notifId);
    expect(notifB!.state, equals(ReviewState.ACTIVE));

    // Device A reconnects to network
    await syncServiceA.setOnline(true);
    await Future.delayed(const Duration(milliseconds: 100));

    // Device B should now have converged to SNOOZED
    notifB = await dbB.notificationDao.getById(notifId);
    expect(notifB!.state, equals(ReviewState.SNOOZED));

    // Device A offline queue marked synced
    final pendingAfterSync = await dbA.offlineSyncQueueDao.getPendingItems();
    expect(pendingAfterSync, isEmpty);
  });
}
