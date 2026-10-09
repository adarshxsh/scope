import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/preferences/user_preferences.dart';

/// Represents a single logged behavioral or telemetry event.
class TelemetryEvent {
  final String eventName;
  final Map<String, dynamic> parameters;
  final DateTime timestamp;

  TelemetryEvent({
    required this.eventName,
    Map<String, dynamic>? parameters,
    DateTime? timestamp,
  })  : parameters = parameters ?? const {},
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'eventName': eventName,
        'parameters': parameters,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// On-device telemetry logging service that respects user privacy preferences.
class TelemetryService {
  final Ref? _ref;
  final List<TelemetryEvent> _events = [];

  TelemetryService([this._ref]);

  /// Returns whether telemetry collection is currently active based on user preferences.
  bool get isTelemetryEnabled {
    if (_ref == null) return true;
    return _ref.read(userPreferencesProvider).telemetryEnabled;
  }

  /// Logs a behavioral event if telemetry is enabled by user preference.
  /// If telemetry is disabled, halts local event collection silently.
  void logEvent(String eventName, [Map<String, dynamic>? parameters]) {
    if (!isTelemetryEnabled) {
      return;
    }
    _events.add(TelemetryEvent(
      eventName: eventName,
      parameters: parameters,
    ));
  }

  /// Returns unmodifiable list of logged events.
  List<TelemetryEvent> get loggedEvents => List.unmodifiable(_events);

  /// Clears all stored telemetry events.
  void clearEvents() {
    _events.clear();
  }
}

/// Riverpod provider for TelemetryService.
final telemetryServiceProvider = Provider<TelemetryService>((ref) {
  return TelemetryService(ref);
});
