import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Thermal state of the device processor/battery.
enum ThermalState {
  normal,   // System operating normally
  fair,     // Slightly elevated, no throttling required
  serious,  // High temperature, requires fast-path fallback
  critical, // Critical throttling, minimal execution required
}

/// Execution strategy selected by dynamic inference guardrails.
enum ExecutionStrategy {
  fullMl,           // Full TFLite model + rule engine execution
  fastPathFallback, // Lightweight heuristic fast-path fallback
}

/// System resource monitor tracking thermal state, battery level,
/// rolling inference latency, and enforcing telemetry/privacy guardrails.
class ThermalGuardrails {
  static ThermalGuardrails? _instance;

  ThermalState _thermalState = ThermalState.normal;
  double _batteryLevel = 1.0; // 0.0 to 1.0 (100%)
  bool _isLowPowerMode = false;

  final Queue<int> _recentLatenciesMs = Queue<int>();
  static const int _maxLatencyWindowSize = 20;
  static const int _latencyThresholdMs = 50;
  static const double _batteryThreshold = 0.15; // 15%

  ThermalGuardrails._();

  static ThermalGuardrails get instance => _instance ??= ThermalGuardrails._();

  /// Reset singleton instance (useful for unit testing).
  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  /// Current device thermal state.
  ThermalState get thermalState => _thermalState;

  /// Current battery level (0.0 to 1.0).
  double get batteryLevel => _batteryLevel;

  /// Whether low power mode is active.
  bool get isLowPowerMode => _isLowPowerMode;

  /// Updates current thermal state.
  void updateThermalState(ThermalState state) {
    _thermalState = state;
  }

  /// Updates current battery level (0.0 to 1.0) and low power mode flag.
  void updateBatteryState({required double batteryLevel, bool isLowPowerMode = false}) {
    _batteryLevel = batteryLevel.clamp(0.0, 1.0);
    _isLowPowerMode = isLowPowerMode;
  }

  /// Records a new processing latency sample (in ms) into rolling window.
  void recordLatency(int latencyMs) {
    _recentLatenciesMs.addLast(latencyMs);
    if (_recentLatenciesMs.length > _maxLatencyWindowSize) {
      _recentLatenciesMs.removeFirst();
    }
  }

  /// Calculates rolling average processing latency in milliseconds.
  double get rollingAverageLatencyMs {
    if (_recentLatenciesMs.isEmpty) return 0.0;
    final total = _recentLatenciesMs.reduce((a, b) => a + b);
    return total / _recentLatenciesMs.length;
  }

  /// Returns whether dynamic fast-path fallback should be engaged due to
  /// resource pressure (high thermal state, low battery, or high rolling latency).
  bool get shouldUseFastPath {
    // Thermal pressure: serious or critical
    if (_thermalState == ThermalState.serious || _thermalState == ThermalState.critical) {
      return true;
    }
    // Battery pressure: low battery (< 15%) or low power mode enabled
    if (_batteryLevel < _batteryThreshold || _isLowPowerMode) {
      return true;
    }
    // Performance pressure: rolling average latency exceeds 50ms benchmark
    if (_recentLatenciesMs.isNotEmpty && rollingAverageLatencyMs > _latencyThresholdMs) {
      return true;
    }
    return false;
  }

  /// Active execution strategy based on resource pressure.
  ExecutionStrategy get activeStrategy =>
      shouldUseFastPath ? ExecutionStrategy.fastPathFallback : ExecutionStrategy.fullMl;

  /// Clears recorded latency window and resets states.
  void clearMetrics() {
    _recentLatenciesMs.clear();
    _thermalState = ThermalState.normal;
    _batteryLevel = 1.0;
    _isLowPowerMode = false;
  }

  /// Redacts and sanitizes cleartext PII (OTPs, credit cards, emails, phone numbers, transaction amounts)
  /// to ensure zero cleartext PII exposure in structured logging or diagnostic telemetry.
  static String sanitizePii(String input) {
    if (input.isEmpty) return input;

    String sanitized = input;

    // Redact emails first
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'),
      (match) => '[REDACTED_EMAIL]',
    );

    // Redact currency amounts
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'(?:Rs\.?|INR|₹|\$|€|£)\s*\d+(?:,\d+)*(?:\.\d+)?', caseSensitive: false),
      (match) => '[REDACTED_AMOUNT]',
    );

    // Redact credit card / account numbers (12-16 digits)
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b'),
      (match) => '[REDACTED_CARD]',
    );

    // Redact phone numbers (10+ digits or formatted)
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b'),
      (match) => '[REDACTED_PHONE]',
    );

    // Redact standalone OTP / verification codes (4-8 digit numbers)
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'\b\d{4,8}\b'),
      (match) => '[REDACTED_CODE]',
    );

    return sanitized;
  }
}
