import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/ingestion_policy.dart';

/// Controller managing pre-ingestion privacy policies, persistent state,
/// and native Android SharedPreferences synchronization.
class IngestionGuardrailController extends ChangeNotifier {
  IngestionGuardrailController({NotificationBridge? bridge})
      : _bridge = bridge ?? NotificationBridge() {
    _loadPolicy();
  }

  final NotificationBridge _bridge;
  IngestionPolicy _policy = IngestionPolicy.defaultPolicy();

  IngestionPolicy get policy => _policy;

  Future<File?> _getPolicyFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/ingestion_policy.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadPolicy() async {
    try {
      final file = await _getPolicyFile();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        _policy = IngestionPolicy.fromMap(map);
        notifyListeners();
      }
    } catch (_) {
      // Fallback to default policy on load error
    }
  }

  Future<void> _savePolicy() async {
    try {
      final file = await _getPolicyFile();
      if (file != null) {
        await file.writeAsString(jsonEncode(_policy.toMap()));
      }
    } catch (_) {
      // Ignore write failure in unsupported environments
    }
    // Sync with native Android SharedPreferences
    await _bridge.syncIngestionPolicy(_policy.toMap());
  }

  /// Updates policy and persists changes locally and across MethodChannel.
  Future<void> updatePolicy(IngestionPolicy newPolicy) async {
    _policy = newPolicy;
    notifyListeners();
    await _savePolicy();
  }

  /// Filters a batch of notifications against the active policy.
  /// Discards blocked/excluded notifications and redacts OTPs in memory.
  List<AppNotification> filterBatch(List<AppNotification> notifications) {
    final result = <AppNotification>[];
    for (final raw in notifications) {
      final processed = _policy.processBeforeIngestion(raw);
      if (processed != null) {
        result.add(processed);
      }
    }
    return result;
  }

  /// Toggles package blocklist state.
  Future<void> togglePackageBlock(String packageName) async {
    final updatedPackages = Set<String>.from(_policy.blockedPackages);
    final pkgLower = packageName.toLowerCase();
    if (updatedPackages.any((p) => p.toLowerCase() == pkgLower)) {
      updatedPackages.removeWhere((p) => p.toLowerCase() == pkgLower);
    } else {
      updatedPackages.add(packageName);
    }
    await updatePolicy(_policy.copyWith(blockedPackages: updatedPackages));
  }

  /// Toggles category exclusion state (e.g. 'finance', 'health', 'social').
  Future<void> toggleCategoryExclusion(String category) async {
    final updatedCategories = Set<String>.from(_policy.excludedCategories);
    final catLower = category.toLowerCase();
    if (updatedCategories.any((c) => c.toLowerCase() == catLower)) {
      updatedCategories.removeWhere((c) => c.toLowerCase() == catLower);
    } else {
      updatedCategories.add(category);
    }
    await updatePolicy(_policy.copyWith(excludedCategories: updatedCategories));
  }

  /// Enables or disables OTP masking.
  Future<void> setOtpMasking(bool enabled) async {
    await updatePolicy(_policy.copyWith(otpMaskingEnabled: enabled));
  }

  /// Enables or disables Financial Protection Mode.
  Future<void> setFinancialProtection(bool enabled) async {
    await updatePolicy(_policy.copyWith(financialProtectionEnabled: enabled));
  }

  /// Enables or disables system noise filtering.
  Future<void> setBlockSystemNoise(bool enabled) async {
    await updatePolicy(_policy.copyWith(blockSystemNoise: enabled));
  }
}
