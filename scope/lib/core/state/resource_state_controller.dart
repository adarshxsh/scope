import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:scope/core/bridge/notification_bridge.dart';

/// Execution policy levels based on device thermal and battery resource state.
enum ExecutionPolicy {
  /// Unconstrained performance: full TFLite inference enabled.
  normal,

  /// Moderately constrained: elevated resource pressure, fast-path heuristic fallback recommended.
  degraded,

  /// Severely constrained: severe/critical thermal status or low battery (<15%). Bypasses TFLite execution.
  critical,
}

/// Controller managing real-time device thermal and battery resource states.
class ResourceStateController extends ChangeNotifier {
  static ResourceStateController? _instance;

  final NotificationBridge _bridge;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  int _thermalStatus = 0; // 0=NONE, 1=LIGHT, 2=MODERATE, 3=SEVERE, 4=CRITICAL, 5=EMERGENCY, 6=SHUTDOWN
  int _batteryLevel = 100;
  bool _isCharging = false;
  ExecutionPolicy? _policyOverride;

  ResourceStateController({NotificationBridge? bridge})
      : _bridge = bridge ?? NotificationBridge();

  static ResourceStateController get instance =>
      _instance ??= ResourceStateController();

  /// Thermal status code (0-6) or -1 if unavailable on Android version.
  int get thermalStatus => _thermalStatus;

  /// Battery level percentage (0-100).
  int get batteryLevel => _batteryLevel;

  /// Whether device is currently charging.
  bool get isCharging => _isCharging;

  /// Active execution policy flag.
  ExecutionPolicy get executionPolicy {
    if (_policyOverride != null) {
      return _policyOverride!;
    }
    // Critical: Thermal severe (3) or critical (4+), or battery below 15%
    if (_thermalStatus >= 3 || (_batteryLevel >= 0 && _batteryLevel < 15)) {
      return ExecutionPolicy.critical;
    }
    // Degraded: Thermal moderate (2) or battery 15-20%
    if (_thermalStatus == 2 || (_batteryLevel >= 15 && _batteryLevel <= 20)) {
      return ExecutionPolicy.degraded;
    }
    return ExecutionPolicy.normal;
  }

  /// Flag indicating whether TFLite model execution should be bypassed under resource pressure.
  bool get shouldBypassTFLite => executionPolicy != ExecutionPolicy.normal;

  /// Initializes subscriptions to native thermal status and battery updates.
  Future<void> initialize() async {
    try {
      final initialMap = await _bridge.getResourceState();
      if (initialMap.isNotEmpty) {
        _applyResourceMap(initialMap);
      }
    } catch (e) {
      debugPrint('ResourceStateController failed to fetch initial state: $e');
    }

    _subscription?.cancel();
    try {
      _subscription = _bridge.resourceStateStream.listen(
        (map) {
          if (map.isNotEmpty) {
            _applyResourceMap(map);
            notifyListeners();
          }
        },
        onError: (err) {
          debugPrint('ResourceStateController stream error: $err');
        },
      );
    } catch (e) {
      debugPrint('ResourceStateController failed to subscribe to stream: $e');
    }
  }

  void _applyResourceMap(Map<String, dynamic> map) {
    if (map.containsKey('thermalStatus') && map['thermalStatus'] is int) {
      _thermalStatus = map['thermalStatus'] as int;
    }
    if (map.containsKey('batteryLevel') && map['batteryLevel'] is int) {
      _batteryLevel = map['batteryLevel'] as int;
    }
    if (map.containsKey('isCharging') && map['isCharging'] is bool) {
      _isCharging = map['isCharging'] as bool;
    }
  }

  /// Manually updates state or applies policy overrides (useful for testing and simulations).
  void updateResourceState({
    int? thermalStatus,
    int? batteryLevel,
    bool? isCharging,
    ExecutionPolicy? policyOverride,
  }) {
    if (thermalStatus != null) _thermalStatus = thermalStatus;
    if (batteryLevel != null) _batteryLevel = batteryLevel;
    if (isCharging != null) _isCharging = isCharging;
    _policyOverride = policyOverride;
    notifyListeners();
  }

  /// Resets state to default normal values and clears overrides.
  void reset() {
    _thermalStatus = 0;
    _batteryLevel = 100;
    _isCharging = false;
    _policyOverride = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
