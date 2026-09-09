import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Represents configurable user settings for data retention, telemetry, and storage quota.
class UserPreferences {
  /// Retention duration in days. -1 represents unlimited retention.
  final int retentionDays;

  /// Whether local behavioral telemetry event logging is enabled (opt-in by default).
  final bool telemetryEnabled;

  /// Database storage quota threshold in MB. -1 represents unlimited quota.
  final int storageQuotaMb;

  const UserPreferences({
    this.retentionDays = 7,
    this.telemetryEnabled = true,
    this.storageQuotaMb = 100,
  });

  UserPreferences copyWith({
    int? retentionDays,
    bool? telemetryEnabled,
    int? storageQuotaMb,
  }) {
    return UserPreferences(
      retentionDays: retentionDays ?? this.retentionDays,
      telemetryEnabled: telemetryEnabled ?? this.telemetryEnabled,
      storageQuotaMb: storageQuotaMb ?? this.storageQuotaMb,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'retentionDays': retentionDays,
      'telemetryEnabled': telemetryEnabled,
      'storageQuotaMb': storageQuotaMb,
    };
  }

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      retentionDays: json['retentionDays'] as int? ?? 7,
      telemetryEnabled: json['telemetryEnabled'] as bool? ?? true,
      storageQuotaMb: json['storageQuotaMb'] as int? ?? 100,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserPreferences &&
        other.retentionDays == retentionDays &&
        other.telemetryEnabled == telemetryEnabled &&
        other.storageQuotaMb == storageQuotaMb;
  }

  @override
  int get hashCode => Object.hash(retentionDays, telemetryEnabled, storageQuotaMb);
}

/// StateNotifier to manage and persist user preferences.
class UserPreferencesNotifier extends StateNotifier<UserPreferences> {
  final File? _storageFile;

  UserPreferencesNotifier([this._storageFile, UserPreferences? initial])
      : super(initial ?? const UserPreferences()) {
    if (_storageFile != null) {
      _loadFromFile();
    } else {
      _initDefaultFileStorage();
    }
  }

  Future<void> _initDefaultFileStorage() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'user_preferences.json'));
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        state = UserPreferences.fromJson(json);
      }
    } catch (_) {
      // Fallback to default state if file reading fails
    }
  }

  Future<void> _loadFromFile() async {
    if (_storageFile == null) return;
    try {
      if (await _storageFile.exists()) {
        final content = await _storageFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        state = UserPreferences.fromJson(json);
      }
    } catch (_) {
      // Keep initial/default state
    }
  }

  Future<void> _save() async {
    try {
      if (_storageFile != null) {
        await _storageFile.writeAsString(jsonEncode(state.toJson()));
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File(p.join(dir.path, 'user_preferences.json'));
        await file.writeAsString(jsonEncode(state.toJson()));
      }
    } catch (_) {
      // Silent error handling for offline/test environments
    }
  }

  Future<void> setRetentionDays(int days) async {
    state = state.copyWith(retentionDays: days);
    await _save();
  }

  Future<void> setTelemetryEnabled(bool enabled) async {
    state = state.copyWith(telemetryEnabled: enabled);
    await _save();
  }

  Future<void> setStorageQuotaMb(int quotaMb) async {
    state = state.copyWith(storageQuotaMb: quotaMb);
    await _save();
  }

  Future<void> resetToDefaults() async {
    state = const UserPreferences();
    await _save();
  }
}

/// Riverpod provider for user preferences.
final userPreferencesProvider =
    StateNotifierProvider<UserPreferencesNotifier, UserPreferences>((ref) {
  return UserPreferencesNotifier();
});
