import 'package:flutter/foundation.dart';

/// Thermal state of the device reported by native thermal monitoring APIs.
enum ThermalState {
  normal,
  warm,
  throttled,
}

/// Service that monitors device thermal state, battery levels, and power modes
/// to expose guardrail signals for AI inference pipeline throttling.
class ThermalGuardrailService {
  static ThermalGuardrailService? _instance;

  ThermalState _thermalState = ThermalState.normal;
  double _batteryLevel = 1.0; // 0.0 to 1.0
  bool _isCharging = false;
  bool _isLowPowerMode = false;

  ThermalGuardrailService._();

  /// Access singleton instance of [ThermalGuardrailService].
  static ThermalGuardrailService get instance =>
      _instance ??= ThermalGuardrailService._();

  /// Gets current thermal state.
  ThermalState get thermalState => _thermalState;

  /// Gets current battery level (0.0 to 1.0).
  double get batteryLevel => _batteryLevel;

  /// Returns whether device is connected to power.
  bool get isCharging => _isCharging;

  /// Returns whether device is operating in system battery saver / low power mode.
  bool get isLowPowerMode => _isLowPowerMode;

  /// Returns whether execution state is normal.
  bool get isNormal => _thermalState == ThermalState.normal;

  /// Returns whether execution state is warm.
  bool get isWarm => _thermalState == ThermalState.warm;

  /// Returns whether execution state is throttled or subject to resource pressure guardrails.
  bool get isThrottled =>
      _thermalState == ThermalState.throttled ||
      (_batteryLevel <= 0.15 && !_isCharging) ||
      _isLowPowerMode;

  /// Explicitly updates thermal state.
  void setThermalState(ThermalState state) {
    _thermalState = state;
    if (kDebugMode) {
      debugPrint('ThermalGuardrailService: Thermal state updated to $state');
    }
  }

  /// Updates battery state and low power mode settings.
  void updateBatteryState({
    required double batteryLevel,
    bool isCharging = false,
    bool isLowPowerMode = false,
  }) {
    _batteryLevel = batteryLevel.clamp(0.0, 1.0);
    _isCharging = isCharging;
    _isLowPowerMode = isLowPowerMode;
    if (kDebugMode) {
      debugPrint(
        'ThermalGuardrailService: Battery updated level=$_batteryLevel, charging=$_isCharging, lowPowerMode=$_isLowPowerMode',
      );
    }
  }

  /// Explicitly updates low power mode state.
  void setLowPowerMode(bool active) {
    _isLowPowerMode = active;
  }

  /// Resets state to default normal state (used for testing).
  void reset() {
    _thermalState = ThermalState.normal;
    _batteryLevel = 1.0;
    _isCharging = false;
    _isLowPowerMode = false;
  }
}
