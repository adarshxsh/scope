import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/preferences/user_preferences.dart';
import 'package:scope/core/telemetry/telemetry_service.dart';

void main() {
  group('TelemetryService', () {
    test('logs events when telemetry is enabled', () {
      final container = ProviderContainer(
        overrides: [
          userPreferencesProvider.overrideWith((ref) => UserPreferencesNotifier(
                null,
                const UserPreferences(telemetryEnabled: true),
              )),
        ],
      );

      final telemetry = container.read(telemetryServiceProvider);

      telemetry.logEvent('user_viewed_notification', {'id': 'n1'});
      telemetry.logEvent('focus_session_started');

      expect(telemetry.loggedEvents.length, equals(2));
      expect(telemetry.loggedEvents.first.eventName, equals('user_viewed_notification'));
      expect(telemetry.loggedEvents.first.parameters['id'], equals('n1'));
    });

    test('halts logging when telemetry is disabled', () {
      final container = ProviderContainer(
        overrides: [
          userPreferencesProvider.overrideWith((ref) => UserPreferencesNotifier(
                null,
                const UserPreferences(telemetryEnabled: false),
              )),
        ],
      );

      final telemetry = container.read(telemetryServiceProvider);

      telemetry.logEvent('user_viewed_notification', {'id': 'n1'});
      telemetry.logEvent('action_completed');

      expect(telemetry.loggedEvents, isEmpty);
    });

    test('clearEvents removes all recorded events', () {
      final telemetry = TelemetryService();
      telemetry.logEvent('test_event');
      expect(telemetry.loggedEvents.length, equals(1));

      telemetry.clearEvents();
      expect(telemetry.loggedEvents, isEmpty);
    });
  });
}
