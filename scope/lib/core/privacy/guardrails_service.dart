import 'package:flutter/foundation.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/analysis/metadata_analyzer.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/daos.dart';

/// Pre-defined sensitive categories for category-level privacy controls.
enum SensitiveCategory {
  bankingOtp('Banking & OTP', 'Financial alerts, transaction updates, and verification codes'),
  health('Health', 'Medical appointments, healthcare alerts, and prescription reminders'),
  messaging('Messaging', 'Chat, messaging, and communication applications');

  final String label;
  final String description;

  const SensitiveCategory(this.label, this.description);

  String get key {
    switch (this) {
      case SensitiveCategory.bankingOtp:
        return 'banking_otp';
      case SensitiveCategory.health:
        return 'health';
      case SensitiveCategory.messaging:
        return 'messaging';
    }
  }

  static SensitiveCategory? fromKey(String key) {
    for (final cat in SensitiveCategory.values) {
      if (cat.key == key) return cat;
    }
    return null;
  }
}

/// Information about a known app package for exclusion settings.
class AppPackageInfo {
  final String packageName;
  final String label;
  final String? categoryHint;
  final bool isExcluded;

  const AppPackageInfo({
    required this.packageName,
    required this.label,
    this.categoryHint,
    required this.isExcluded,
  });
}

/// Service managing category-level privacy guardrails and per-app package exclusions.
class GuardrailService extends ChangeNotifier {
  final AttentionDatabase? _db;

  Set<SensitiveCategory> _mutedCategories = {};
  Set<String> _excludedPackages = {};
  bool _isInitialized = false;

  GuardrailService([this._db]) {
    _loadSettings();
  }

  bool get isInitialized => _isInitialized;
  Set<SensitiveCategory> get mutedCategories => Set.unmodifiable(_mutedCategories);
  Set<String> get excludedPackages => Set.unmodifiable(_excludedPackages);

  bool isCategoryMuted(SensitiveCategory category) => _mutedCategories.contains(category);
  bool isPackageExcluded(String packageName) => _excludedPackages.contains(packageName.toLowerCase());

  Future<void> _loadSettings() async {
    if (_db != null) {
      try {
        final dao = GuardrailDao(_db);
        final mutedCatStr = await dao.getSetting('muted_categories');
        if (mutedCatStr != null && mutedCatStr.isNotEmpty) {
          _mutedCategories = mutedCatStr
              .split(',')
              .map((k) => SensitiveCategory.fromKey(k.trim()))
              .whereType<SensitiveCategory>()
              .toSet();
        }

        final excludedPkgStr = await dao.getSetting('excluded_packages');
        if (excludedPkgStr != null && excludedPkgStr.isNotEmpty) {
          _excludedPackages = excludedPkgStr
              .split(',')
              .map((p) => p.trim().toLowerCase())
              .where((p) => p.isNotEmpty)
              .toSet();
        }
      } catch (e) {
        // Fallback to memory defaults
      }
    }
    _isInitialized = true;
    notifyListeners();
  }

  /// Determines if an incoming notification should be dropped before AI analysis and storage.
  bool shouldDrop(AppNotification notification) {
    // 1. Check package exclusion
    if (isPackageExcluded(notification.packageName)) {
      return true;
    }

    // 2. Check category guardrails
    for (final category in _mutedCategories) {
      if (matchesCategory(notification, category)) {
        return true;
      }
    }

    return false;
  }

  /// Evaluates if a notification belongs to a specific sensitive category.
  bool matchesCategory(AppNotification notification, SensitiveCategory category) {
    final pkg = notification.packageName.toLowerCase();
    final rawCat = (notification.category ?? '').toLowerCase();
    final classifiedCat = (notification.classifiedCategory ?? '').toLowerCase();
    final hintCat = (MetadataAnalyzer.getCategoryHint(notification) ?? '').toLowerCase();
    final title = notification.title.toLowerCase();
    final content = notification.content.toLowerCase();
    final combined = '$title $content';

    switch (category) {
      case SensitiveCategory.bankingOtp:
        // Package level hints
        final isKnownFinancePkg = pkg.contains('bank') ||
            pkg.contains('paytm') ||
            pkg.contains('phonepe') ||
            pkg.contains('groww') ||
            pkg.contains('zerodha') ||
            pkg.contains('gpay') ||
            hintCat == 'finance';

        if (isKnownFinancePkg) return true;

        // Category matching
        if (rawCat == 'finance' || rawCat == 'banking' || rawCat == 'otp' ||
            classifiedCat == 'finance' || classifiedCat == 'banking' || classifiedCat == 'otp') {
          return true;
        }

        // Feature / Pattern matching
        final extracted = FeatureExtractor.extract(title: notification.title, content: notification.content);
        if (extracted.otp != null || extracted.amount != null) {
          return true;
        }

        // Keywords matching
        final bankingKeywords = [
          'otp',
          'verification code',
          'passcode',
          'security code',
          'one time password',
          'one-time password',
          'debited',
          'credited',
          'bank',
          'account balance',
          'upi',
          'transaction',
        ];
        for (final kw in bankingKeywords) {
          if (combined.contains(kw)) return true;
        }

        return false;

      case SensitiveCategory.health:
        if (hintCat == 'health' || rawCat == 'health' || classifiedCat == 'health') {
          return true;
        }
        if (pkg.contains('health') || pkg.contains('apollo') || pkg.contains('practo')) {
          return true;
        }

        final healthKeywords = [
          'doctor',
          'prescription',
          'hospital',
          'patient',
          'medical',
          'health',
          'clinic',
          'medicine',
          'lab test',
        ];
        for (final kw in healthKeywords) {
          if (combined.contains(kw)) return true;
        }

        return false;

      case SensitiveCategory.messaging:
        if (hintCat == 'msg' || rawCat == 'msg' || rawCat == 'messaging' ||
            classifiedCat == 'msg' || classifiedCat == 'messaging' || rawCat == 'im') {
          return true;
        }

        final knownMessagingPkgs = [
          'com.whatsapp',
          'com.slack',
          'org.telegram.messenger',
          'com.facebook.orca',
          'com.google.android.apps.messaging',
          'com.discord',
          'com.signal',
        ];
        if (knownMessagingPkgs.contains(pkg) || pkg.contains('message') || pkg.contains('chat')) {
          return true;
        }

        return false;
    }
  }

  /// Toggles a sensitive category on or off.
  /// Setting [muted] to true mutes the category and triggers retroactive purge.
  Future<void> toggleCategory(SensitiveCategory category, bool muted) async {
    if (muted) {
      _mutedCategories.add(category);
    } else {
      _mutedCategories.remove(category);
    }

    if (_db != null) {
      final dao = GuardrailDao(_db);
      final value = _mutedCategories.map((c) => c.key).join(',');
      await dao.setSetting('muted_categories', value);
    }

    notifyListeners();
  }

  /// Toggles app exclusion for a specific package name.
  /// Setting [excluded] to true mutes the app and triggers retroactive purge.
  Future<void> togglePackage(String packageName, bool excluded) async {
    final lowerPkg = packageName.toLowerCase();
    if (excluded) {
      _excludedPackages.add(lowerPkg);
    } else {
      _excludedPackages.remove(lowerPkg);
    }

    if (_db != null) {
      final dao = GuardrailDao(_db);
      final value = _excludedPackages.join(',');
      await dao.setSetting('excluded_packages', value);
    }

    notifyListeners();
  }

  /// Helper to map known app package metadata for settings view.
  List<AppPackageInfo> getAppList(List<AppNotification> currentNotifications) {
    final Map<String, AppPackageInfo> apps = {};

    // 1. Known predefined packages
    MetadataAnalyzer.packageCategoryMap.forEach((pkg, category) {
      final label = _deriveAppLabel(pkg);
      apps[pkg] = AppPackageInfo(
        packageName: pkg,
        label: label,
        categoryHint: category,
        isExcluded: isPackageExcluded(pkg),
      );
    });

    // 2. Discover packages from current notifications
    for (final n in currentNotifications) {
      final pkg = n.packageName;
      if (!apps.containsKey(pkg)) {
        apps[pkg] = AppPackageInfo(
          packageName: pkg,
          label: _deriveAppLabel(pkg),
          categoryHint: n.classifiedCategory ?? n.category ?? MetadataAnalyzer.getCategoryHint(n),
          isExcluded: isPackageExcluded(pkg),
        );
      }
    }

    // 3. Include any additional user-excluded packages not in map
    for (final pkg in _excludedPackages) {
      if (!apps.containsKey(pkg)) {
        apps[pkg] = AppPackageInfo(
          packageName: pkg,
          label: _deriveAppLabel(pkg),
          categoryHint: null,
          isExcluded: true,
        );
      }
    }

    final sorted = apps.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    return sorted;
  }

  static String _deriveAppLabel(String packageName) {
    final parts = packageName.split('.');
    if (parts.length >= 2) {
      var name = parts.last;
      if (name == 'android' || name == 'app' || name == 'messenger' || name == 'mShop') {
        if (parts.length >= 3) name = parts[parts.length - 2];
      }
      return name[0].toUpperCase() + name.substring(1);
    }
    return packageName;
  }
}
