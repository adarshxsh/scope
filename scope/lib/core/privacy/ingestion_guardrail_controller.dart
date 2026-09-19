import 'package:flutter/services.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/guardrails/ingestion_guardrails.dart';

/// Controller for managing ingestion policy state and syncing with native Android collector.
class IngestionGuardrailController {
  final IngestionGuardrailService service;

  IngestionGuardrailController({IngestionGuardrailService? service})
      : service = service ?? IngestionGuardrailService();

  IngestionPolicy get policy => service.policy;
  List<IngestionAuditLog> get auditLogs => service.auditLogs;

  /// Loads initial policy settings from asset bundle if present.
  Future<void> initializeFromAsset([AssetBundle? bundle]) async {
    try {
      final b = bundle ?? rootBundle;
      final jsonStr = await b.loadString('assets/ingestion_policy.json');
      final policy = IngestionPolicy.fromJson(jsonStr);
      service.updatePolicy(policy);
    } catch (_) {
      // Keep existing/default policy on error
    }
  }

  void addBlacklistedPackage(String pkg) {
    final updated = Set<String>.from(policy.blacklistedPackages)..add(pkg.trim());
    service.updatePolicy(policy.copyWith(blacklistedPackages: updated));
  }

  void removeBlacklistedPackage(String pkg) {
    final updated = Set<String>.from(policy.blacklistedPackages)..remove(pkg.trim());
    service.updatePolicy(policy.copyWith(blacklistedPackages: updated));
  }

  void addWhitelistedPackage(String pkg) {
    final updated = Set<String>.from(policy.whitelistedPackages)..add(pkg.trim());
    service.updatePolicy(policy.copyWith(whitelistedPackages: updated));
  }

  void removeWhitelistedPackage(String pkg) {
    final updated = Set<String>.from(policy.whitelistedPackages)..remove(pkg.trim());
    service.updatePolicy(policy.copyWith(whitelistedPackages: updated));
  }

  void setWhitelistingEnabled(bool enabled) {
    service.updatePolicy(policy.copyWith(isWhitelistingEnabled: enabled));
  }

  void addExcludedCategory(String category) {
    final updated = Set<String>.from(policy.excludedCategories)..add(category.trim().toLowerCase());
    service.updatePolicy(policy.copyWith(excludedCategories: updated));
  }

  void removeExcludedCategory(String category) {
    final updated = Set<String>.from(policy.excludedCategories)..remove(category.trim().toLowerCase());
    service.updatePolicy(policy.copyWith(excludedCategories: updated));
  }

  /// Syncs current policy settings to Android native SharedPreferences via MethodChannel.
  Future<bool> syncToNative(NotificationBridge bridge) async {
    return await bridge.syncIngestionPolicy(policy.toMap());
  }
}
