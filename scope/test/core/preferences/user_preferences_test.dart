import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/preferences/user_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserPreferences', () {
    test('default values', () {
      const prefs = UserPreferences();
      expect(prefs.retentionDays, equals(7));
      expect(prefs.telemetryEnabled, isTrue);
      expect(prefs.storageQuotaMb, equals(100));
    });

    test('copyWith updates specified fields', () {
      const prefs = UserPreferences();
      final updated = prefs.copyWith(
        retentionDays: 14,
        telemetryEnabled: false,
        storageQuotaMb: 250,
      );

      expect(updated.retentionDays, equals(14));
      expect(updated.telemetryEnabled, isFalse);
      expect(updated.storageQuotaMb, equals(250));
    });

    test('toJson and fromJson round-trip', () {
      const original = UserPreferences(
        retentionDays: 30,
        telemetryEnabled: false,
        storageQuotaMb: 500,
      );

      final json = original.toJson();
      final restored = UserPreferences.fromJson(json);

      expect(restored, equals(original));
    });

    test('equality and hashCode', () {
      const a = UserPreferences(retentionDays: 3, telemetryEnabled: true, storageQuotaMb: 50);
      const b = UserPreferences(retentionDays: 3, telemetryEnabled: true, storageQuotaMb: 50);
      const c = UserPreferences(retentionDays: 7, telemetryEnabled: true, storageQuotaMb: 50);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('UserPreferencesNotifier', () {
    late File tempFile;

    setUp(() {
      final tempDir = Directory.systemTemp.createTempSync('prefs_test');
      tempFile = File('${tempDir.path}/user_preferences.json');
    });

    tearDown(() {
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
    });

    test('updates state and persists to file', () async {
      final notifier = UserPreferencesNotifier(tempFile);

      await notifier.setRetentionDays(3);
      expect(notifier.state.retentionDays, equals(3));

      await notifier.setTelemetryEnabled(false);
      expect(notifier.state.telemetryEnabled, isFalse);

      await notifier.setStorageQuotaMb(50);
      expect(notifier.state.storageQuotaMb, equals(50));

      expect(tempFile.existsSync(), isTrue);

      // Reload from same file to verify persistence
      final restoredNotifier = UserPreferencesNotifier(tempFile);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(restoredNotifier.state.retentionDays, equals(3));
      expect(restoredNotifier.state.telemetryEnabled, isFalse);
      expect(restoredNotifier.state.storageQuotaMb, equals(50));
    });

    test('resetToDefaults restores default values', () async {
      final notifier = UserPreferencesNotifier(tempFile);
      await notifier.setRetentionDays(30);
      await notifier.setTelemetryEnabled(false);

      await notifier.resetToDefaults();

      expect(notifier.state.retentionDays, equals(7));
      expect(notifier.state.telemetryEnabled, isTrue);
      expect(notifier.state.storageQuotaMb, equals(100));
    });
  });
}
