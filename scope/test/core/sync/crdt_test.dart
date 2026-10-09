import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/sync/crdt.dart';

void main() {
  group('VectorClock Tests', () {
    test('VectorClock initialization and serialization', () {
      const vc1 = VectorClock({'device_A': 1, 'device_B': 3});
      final jsonStr = vc1.toJson();
      final vc2 = VectorClock.fromJson(jsonStr);

      expect(vc2.clock['device_A'], equals(1));
      expect(vc2.clock['device_B'], equals(3));
      expect(vc1, equals(vc2));
    });

    test('VectorClock increment', () {
      const vc1 = VectorClock({'device_A': 1});
      final vc2 = vc1.increment('device_A');
      final vc3 = vc2.increment('device_B');

      expect(vc2.clock['device_A'], equals(2));
      expect(vc3.clock['device_A'], equals(2));
      expect(vc3.clock['device_B'], equals(1));
    });

    test('VectorClock merge taking component-wise maximum', () {
      const vc1 = VectorClock({'device_A': 2, 'device_B': 1});
      const vc2 = VectorClock({'device_B': 4, 'device_C': 3});
      final merged = vc1.merge(vc2);

      expect(merged.clock['device_A'], equals(2));
      expect(merged.clock['device_B'], equals(4));
      expect(merged.clock['device_C'], equals(3));
    });

    test('VectorClock compare order evaluation', () {
      const vc1 = VectorClock({'device_A': 1, 'device_B': 2});
      const vc2 = VectorClock({'device_A': 2, 'device_B': 2});
      const vc3 = VectorClock({'device_A': 2, 'device_B': 1});
      const vc4 = VectorClock({'device_A': 1, 'device_B': 2});

      expect(vc1.compare(vc2), equals(VectorClockOrder.less));
      expect(vc2.compare(vc1), equals(VectorClockOrder.greater));
      expect(vc1.compare(vc4), equals(VectorClockOrder.equal));
      expect(vc1.compare(vc3), equals(VectorClockOrder.concurrent));
    });
  });

  group('CrdtStateResolver Tests', () {
    test('resolveNotificationDelta strictly higher vector clock wins', () {
      const localVc = VectorClock({'device_A': 1});
      const remoteVc = VectorClock({'device_A': 2});

      final localDelta = NotificationStateDelta(
        notificationId: 'notif_1',
        state: ReviewState.ACTIVE,
        originDeviceId: 'device_A',
        vectorClock: localVc,
        timestamp: 1000,
      );

      final remoteDelta = NotificationStateDelta(
        notificationId: 'notif_1',
        state: ReviewState.REVIEWED,
        originDeviceId: 'device_A',
        vectorClock: remoteVc,
        timestamp: 900,
      );

      final resolved = CrdtStateResolver.resolveNotificationDelta(localDelta, remoteDelta);

      expect(resolved.state, equals(ReviewState.REVIEWED));
      expect(resolved.vectorClock.clock['device_A'], equals(2));
    });

    test('resolveNotificationDelta concurrent vector clocks fall back to LWW timestamp', () {
      const localVc = VectorClock({'device_A': 2, 'device_B': 1});
      const remoteVc = VectorClock({'device_A': 1, 'device_B': 3});

      final localDelta = NotificationStateDelta(
        notificationId: 'notif_1',
        state: ReviewState.ACTIVE,
        originDeviceId: 'device_A',
        vectorClock: localVc,
        timestamp: 1000,
      );

      final remoteDelta = NotificationStateDelta(
        notificationId: 'notif_1',
        state: ReviewState.SNOOZED,
        snoozedUntil: DateTime.fromMillisecondsSinceEpoch(200000, isUtc: true),
        originDeviceId: 'device_B',
        vectorClock: remoteVc,
        timestamp: 1200, // Remote timestamp is later
      );

      final resolved = CrdtStateResolver.resolveNotificationDelta(localDelta, remoteDelta);

      expect(resolved.state, equals(ReviewState.SNOOZED));
      expect(resolved.snoozedUntil, equals(DateTime.fromMillisecondsSinceEpoch(200000, isUtc: true)));
      // Merged clock should contain max of both
      expect(resolved.vectorClock.clock['device_A'], equals(2));
      expect(resolved.vectorClock.clock['device_B'], equals(3));
    });

    test('resolveNotificationDelta timestamp tie-break uses deterministic deviceId ordering', () {
      const localVc = VectorClock({'device_A': 1, 'device_B': 1});
      const remoteVc = VectorClock({'device_A': 1, 'device_B': 1});

      final localDelta = NotificationStateDelta(
        notificationId: 'notif_1',
        state: ReviewState.EXPIRED,
        originDeviceId: 'device_A',
        vectorClock: localVc,
        timestamp: 1000,
      );

      final remoteDelta = NotificationStateDelta(
        notificationId: 'notif_1',
        state: ReviewState.ARCHIVED,
        originDeviceId: 'device_B', // 'device_B' > 'device_A'
        vectorClock: remoteVc,
        timestamp: 1000,
      );

      final resolved = CrdtStateResolver.resolveNotificationDelta(localDelta, remoteDelta);

      expect(resolved.state, equals(ReviewState.ARCHIVED));
      expect(resolved.originDeviceId, equals('device_B'));
    });

    test('resolveRuleDelta merges RLHF custom rule additions and tombstones cleanly', () {
      const localVc = VectorClock({'device_A': 1});
      const remoteVc = VectorClock({'device_A': 1, 'device_B': 2});

      const rule = NotificationRule(
        id: 'rlhf-1',
        category: 'finance',
        priority: 'high',
        conditions: RuleCondition(packages: ['com.bank.app']),
      );

      final localDelta = RlhfRuleDelta(
        ruleId: 'rlhf-1',
        rule: rule,
        isDeleted: false,
        originDeviceId: 'device_A',
        vectorClock: localVc,
        timestamp: 1000,
      );

      final remoteDelta = RlhfRuleDelta(
        ruleId: 'rlhf-1',
        rule: null,
        isDeleted: true,
        originDeviceId: 'device_B',
        vectorClock: remoteVc,
        timestamp: 1500,
      );

      final resolved = CrdtStateResolver.resolveRuleDelta(localDelta, remoteDelta);

      expect(resolved.isDeleted, isTrue);
      expect(resolved.vectorClock.clock['device_B'], equals(2));
    });
  });
}
