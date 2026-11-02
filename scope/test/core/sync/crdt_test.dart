import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/sync/crdt.dart';

void main() {
  group('VectorClock Unit Tests', () {
    test('VectorClock initialization and serialization', () {
      const vc1 = VectorClock({'devA': 1, 'devB': 2});
      expect(vc1.clock['devA'], equals(1));
      expect(vc1.clock['devB'], equals(2));

      final jsonStr = vc1.toJson();
      final vc2 = VectorClock.fromJson(jsonStr);
      expect(vc2, equals(vc1));
    });

    test('VectorClock incrementing and merging', () {
      const vc1 = VectorClock({'devA': 1});
      final vc1Inc = vc1.increment('devA');
      expect(vc1Inc.clock['devA'], equals(2));

      const vc2 = VectorClock({'devA': 1, 'devB': 3});
      final merged = vc1Inc.merge(vc2);
      expect(merged.clock['devA'], equals(2));
      expect(merged.clock['devB'], equals(3));
    });

    test('VectorClock causal order comparisons', () {
      const vc1 = VectorClock({'devA': 2, 'devB': 1});
      const vc2 = VectorClock({'devA': 1, 'devB': 1});
      expect(vc1.compare(vc2), equals(VectorClockOrder.greater));
      expect(vc2.compare(vc1), equals(VectorClockOrder.less));

      const vcConcurrent = VectorClock({'devA': 1, 'devB': 2});
      expect(vc1.compare(vcConcurrent), equals(VectorClockOrder.concurrent));
    });
  });

  group('CrdtStateResolver Unit Tests', () {
    test('Resolves notification review state using vector clock causal order', () {
      final localDelta = NotificationStateDelta(
        notificationId: 'notif-100',
        state: ReviewState.ACTIVE,
        originDeviceId: 'devA',
        vectorClock: const VectorClock({'devA': 1}),
        timestamp: 1000,
      );

      final remoteDelta = NotificationStateDelta(
        notificationId: 'notif-100',
        state: ReviewState.REVIEWED,
        originDeviceId: 'devB',
        vectorClock: const VectorClock({'devA': 1, 'devB': 1}),
        timestamp: 1050,
      );

      final resolved = CrdtStateResolver.resolveNotificationDelta(localDelta, remoteDelta);
      expect(resolved.state, equals(ReviewState.REVIEWED));
      expect(resolved.vectorClock.clock['devA'], equals(1));
      expect(resolved.vectorClock.clock['devB'], equals(1));
    });

    test('Resolves concurrent notification state updates using LWW timestamp fallback', () {
      final localDelta = NotificationStateDelta(
        notificationId: 'notif-101',
        state: ReviewState.SNOOZED,
        originDeviceId: 'devA',
        vectorClock: const VectorClock({'devA': 2, 'devB': 1}),
        timestamp: 2000,
      );

      final remoteDelta = NotificationStateDelta(
        notificationId: 'notif-101',
        state: ReviewState.ARCHIVED,
        originDeviceId: 'devB',
        vectorClock: const VectorClock({'devA': 1, 'devB': 2}),
        timestamp: 2500,
      );

      final resolved = CrdtStateResolver.resolveNotificationDelta(localDelta, remoteDelta);
      expect(resolved.state, equals(ReviewState.ARCHIVED));
      expect(resolved.vectorClock.clock['devA'], equals(2));
      expect(resolved.vectorClock.clock['devB'], equals(2));
    });

    test('Resolves RLHF custom rule deltas accurately', () {
      const rule = NotificationRule(
        id: 'rlhf-rule-01',
        category: 'finance',
        priority: 'high',
        conditions: RuleCondition(
          keywords: ['bank', 'transfer'],
        ),
      );

      final localDelta = RlhfRuleDelta(
        ruleId: rule.id,
        rule: rule,
        isDeleted: false,
        originDeviceId: 'devA',
        vectorClock: const VectorClock({'devA': 1}),
        timestamp: 5000,
      );

      final remoteDelta = RlhfRuleDelta(
        ruleId: rule.id,
        rule: rule,
        isDeleted: true, // Deleted remotely
        originDeviceId: 'devB',
        vectorClock: const VectorClock({'devA': 1, 'devB': 1}),
        timestamp: 5100,
      );

      final resolved = CrdtStateResolver.resolveRuleDelta(localDelta, remoteDelta);
      expect(resolved.isDeleted, isTrue);
    });
  });
}
