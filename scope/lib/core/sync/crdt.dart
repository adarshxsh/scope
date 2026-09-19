import 'dart:convert';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';

enum VectorClockOrder {
  equal,
  less,
  greater,
  concurrent,
}

/// Vector Clock for multi-device CRDT causal ordering.
class VectorClock {
  final Map<String, int> clock;

  const VectorClock([this.clock = const {}]);

  factory VectorClock.fromMap(Map<String, dynamic> map) {
    final parsedMap = <String, int>{};
    map.forEach((key, value) {
      if (value is num) {
        parsedMap[key] = value.toInt();
      }
    });
    return VectorClock(parsedMap);
  }

  factory VectorClock.fromJson(String jsonStr) {
    if (jsonStr.isEmpty) return const VectorClock({});
    try {
      final decoded = json.decode(jsonStr) as Map<String, dynamic>;
      return VectorClock.fromMap(decoded);
    } catch (_) {
      return const VectorClock({});
    }
  }

  Map<String, int> toMap() => Map.unmodifiable(clock);

  String toJson() => json.encode(clock);

  VectorClock increment(String deviceId) {
    final newClock = Map<String, int>.from(clock);
    newClock[deviceId] = (newClock[deviceId] ?? 0) + 1;
    return VectorClock(newClock);
  }

  VectorClock merge(VectorClock other) {
    final merged = Map<String, int>.from(clock);
    other.clock.forEach((deviceId, counter) {
      final current = merged[deviceId] ?? 0;
      if (counter > current) {
        merged[deviceId] = counter;
      }
    });
    return VectorClock(merged);
  }

  VectorClockOrder compare(VectorClock other) {
    final allKeys = {...clock.keys, ...other.clock.keys};
    bool hasGreater = false;
    bool hasLess = false;

    for (final key in allKeys) {
      final v1 = clock[key] ?? 0;
      final v2 = other.clock[key] ?? 0;
      if (v1 > v2) hasGreater = true;
      if (v1 < v2) hasLess = true;
    }

    if (hasGreater && hasLess) return VectorClockOrder.concurrent;
    if (hasGreater) return VectorClockOrder.greater;
    if (hasLess) return VectorClockOrder.less;
    return VectorClockOrder.equal;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! VectorClock) return false;
    return compare(other) == VectorClockOrder.equal;
  }

  @override
  int get hashCode {
    int h = 0;
    clock.forEach((k, v) {
      h ^= k.hashCode ^ v.hashCode;
    });
    return h;
  }

  @override
  String toString() => 'VectorClock($clock)';
}

/// Notification review state CRDT delta payload.
class NotificationStateDelta {
  final String notificationId;
  final ReviewState state;
  final DateTime? snoozedUntil;
  final String originDeviceId;
  final VectorClock vectorClock;
  final int timestamp; // Monotonic UTC epoch millis

  const NotificationStateDelta({
    required this.notificationId,
    required this.state,
    this.snoozedUntil,
    required this.originDeviceId,
    required this.vectorClock,
    required this.timestamp,
  });

  factory NotificationStateDelta.fromMap(Map<String, dynamic> map) {
    return NotificationStateDelta(
      notificationId: map['notification_id'] as String? ?? '',
      state: ReviewState.values.firstWhere(
        (e) => e.name == map['state'],
        orElse: () => ReviewState.ACTIVE,
      ),
      snoozedUntil: map['snoozed_until'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['snoozed_until'] as int, isUtc: true)
          : null,
      originDeviceId: map['origin_device_id'] as String? ?? '',
      vectorClock: VectorClock.fromMap(
        Map<String, dynamic>.from(map['vector_clock'] as Map? ?? {}),
      ),
      timestamp: map['timestamp'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'notification_id': notificationId,
      'state': state.name,
      'snoozed_until': snoozedUntil?.millisecondsSinceEpoch,
      'origin_device_id': originDeviceId,
      'vector_clock': vectorClock.toMap(),
      'timestamp': timestamp,
    };
  }

  factory NotificationStateDelta.fromJson(String jsonStr) {
    return NotificationStateDelta.fromMap(json.decode(jsonStr) as Map<String, dynamic>);
  }

  String toJson() => json.encode(toMap());

  NotificationStateDelta copyWith({
    String? notificationId,
    ReviewState? state,
    DateTime? snoozedUntil,
    String? originDeviceId,
    VectorClock? vectorClock,
    int? timestamp,
  }) {
    return NotificationStateDelta(
      notificationId: notificationId ?? this.notificationId,
      state: state ?? this.state,
      snoozedUntil: snoozedUntil ?? this.snoozedUntil,
      originDeviceId: originDeviceId ?? this.originDeviceId,
      vectorClock: vectorClock ?? this.vectorClock,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// RLHF custom rule CRDT delta payload (LWW-Element-Set CRDT).
class RlhfRuleDelta {
  final String ruleId;
  final NotificationRule? rule;
  final bool isDeleted;
  final String originDeviceId;
  final VectorClock vectorClock;
  final int timestamp; // Monotonic UTC epoch millis

  const RlhfRuleDelta({
    required this.ruleId,
    this.rule,
    this.isDeleted = false,
    required this.originDeviceId,
    required this.vectorClock,
    required this.timestamp,
  });

  factory RlhfRuleDelta.fromMap(Map<String, dynamic> map) {
    return RlhfRuleDelta(
      ruleId: map['rule_id'] as String? ?? '',
      rule: map['rule'] != null
          ? NotificationRule.fromMap(Map<String, dynamic>.from(map['rule'] as Map))
          : null,
      isDeleted: map['is_deleted'] as bool? ?? false,
      originDeviceId: map['origin_device_id'] as String? ?? '',
      vectorClock: VectorClock.fromMap(
        Map<String, dynamic>.from(map['vector_clock'] as Map? ?? {}),
      ),
      timestamp: map['timestamp'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'rule_id': ruleId,
      'rule': rule?.toMap(),
      'is_deleted': isDeleted,
      'origin_device_id': originDeviceId,
      'vector_clock': vectorClock.toMap(),
      'timestamp': timestamp,
    };
  }

  factory RlhfRuleDelta.fromJson(String jsonStr) {
    return RlhfRuleDelta.fromMap(json.decode(jsonStr) as Map<String, dynamic>);
  }

  String toJson() => json.encode(toMap());

  RlhfRuleDelta copyWith({
    String? ruleId,
    NotificationRule? rule,
    bool? isDeleted,
    String? originDeviceId,
    VectorClock? vectorClock,
    int? timestamp,
  }) {
    return RlhfRuleDelta(
      ruleId: ruleId ?? this.ruleId,
      rule: rule ?? this.rule,
      isDeleted: isDeleted ?? this.isDeleted,
      originDeviceId: originDeviceId ?? this.originDeviceId,
      vectorClock: vectorClock ?? this.vectorClock,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Convergence resolver implementing causal order (VectorClock) and LWW timestamp fallback.
class CrdtStateResolver {
  /// Resolves conflicts between local and remote notification state deltas.
  static NotificationStateDelta resolveNotificationDelta(
    NotificationStateDelta local,
    NotificationStateDelta remote,
  ) {
    final mergedClock = local.vectorClock.merge(remote.vectorClock);
    final order = local.vectorClock.compare(remote.vectorClock);

    if (order == VectorClockOrder.greater) {
      return local.copyWith(vectorClock: mergedClock);
    }
    if (order == VectorClockOrder.less) {
      return remote.copyWith(vectorClock: mergedClock);
    }

    // Concurrent or equal clocks: fall back to Last-Write-Wins (LWW) via UTC timestamp
    if (remote.timestamp > local.timestamp) {
      return remote.copyWith(vectorClock: mergedClock);
    }
    if (local.timestamp > remote.timestamp) {
      return local.copyWith(vectorClock: mergedClock);
    }

    // Deterministic tie-breaking if timestamps match exactly: deviceId lexicographical comparison
    if (remote.originDeviceId.compareTo(local.originDeviceId) > 0) {
      return remote.copyWith(vectorClock: mergedClock);
    }
    return local.copyWith(vectorClock: mergedClock);
  }

  /// Resolves conflicts between local and remote RLHF rule deltas.
  static RlhfRuleDelta resolveRuleDelta(
    RlhfRuleDelta local,
    RlhfRuleDelta remote,
  ) {
    final mergedClock = local.vectorClock.merge(remote.vectorClock);
    final order = local.vectorClock.compare(remote.vectorClock);

    if (order == VectorClockOrder.greater) {
      return local.copyWith(vectorClock: mergedClock);
    }
    if (order == VectorClockOrder.less) {
      return remote.copyWith(vectorClock: mergedClock);
    }

    // Concurrent or equal clocks: fall back to LWW timestamp
    if (remote.timestamp > local.timestamp) {
      return remote.copyWith(vectorClock: mergedClock);
    }
    if (local.timestamp > remote.timestamp) {
      return local.copyWith(vectorClock: mergedClock);
    }

    // Tie-break via originDeviceId
    if (remote.originDeviceId.compareTo(local.originDeviceId) > 0) {
      return remote.copyWith(vectorClock: mergedClock);
    }
    return local.copyWith(vectorClock: mergedClock);
  }
}
