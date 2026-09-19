import 'package:flutter/foundation.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';

/// Data class representing an application's exclusion settings and metadata.
class AppExclusionItem {
  final String packageName;
  final String appName;
  final String category; // 'banking', 'otp', 'health', 'general'
  final bool isExcluded;
  final bool isDefaultSensitive;
  final DateTime updatedAt;

  const AppExclusionItem({
    required this.packageName,
    required this.appName,
    required this.category,
    required this.isExcluded,
    this.isDefaultSensitive = false,
    required this.updatedAt,
  });

  AppExclusionItem copyWith({
    String? packageName,
    String? appName,
    String? category,
    bool? isExcluded,
    bool? isDefaultSensitive,
    DateTime? updatedAt,
  }) {
    return AppExclusionItem(
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      category: category ?? this.category,
      isExcluded: isExcluded ?? this.isExcluded,
      isDefaultSensitive: isDefaultSensitive ?? this.isDefaultSensitive,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Manages sensitive app category exclusion rules, user toggles, and persistence.
class AppExclusionManager extends ChangeNotifier {
  final AttentionDatabase? _db;

  // In-memory cache of user-defined overrides for <1ms execution speed
  final Map<String, bool> _customOverrides = {};
  final Map<String, AppExclusionItem> _customItems = {};
  bool _initialized = false;

  AppExclusionManager([this._db]);

  bool get isInitialized => _initialized;

  /// Default Banking & Financial App Packages
  static const Set<String> defaultBankingPackages = {
    'com.chase.sig.android',
    'com.bankofamerica.mft.mobile.banking',
    'com.wellsfargo.mobile',
    'com.citi.citimobile',
    'com.citibank.mobile.india',
    'com.phonepe.app',
    'net.one97.paytm',
    'com.icicibank.mobile.banking',
    'com.sbi.lotusintouch',
    'com.hdfcbank.payzapp',
    'com.axis.mobile',
    'com.paypal.android.p2pmobile',
    'com.venmo',
    'com.revolut.revolut',
    'com.robinhood.android',
    'com.zerodha.kite3',
    'com.nextbillion.groww',
    'com.akbank.android',
    'com.yapikredi.mobile',
    'de.commerzbank.mobile',
    'com.td',
    'com.sc.mobile.in',
    'com.capitalone.mobile.android',
    'com.hsbc.hsbcuk',
    'com.schwab.mobile',
    'com.fidelity.android',
    'com.vanguard.android',
    'com.monzo.app',
    'com.n26.a26',
  };

  /// Default OTP & 2FA Authenticator Packages
  static const Set<String> defaultOtpPackages = {
    'com.google.android.apps.authenticator2',
    'com.duosecurity.duomobile',
    'com.authy.authy',
    'com.azure.authenticator',
    'com.microsoft.emmx',
    'com.yubico.yubioath',
    'com.saaspass',
    'org.fedorahosted.freeotp',
    'com.steam.messenger',
    'com.bip.authenticator',
    'com.enpass.app',
    'com.1password.1password',
    'com.bitwarden.authenticator',
    'com.lastpass.authenticator',
  };

  /// Default Healthcare & Medical App Packages
  static const Set<String> defaultHealthPackages = {
    'com.myfitnesspal.android',
    'com.practo.fabric',
    'com.1mg.myra',
    'com.myupchar',
    'com.teladoc.members',
    'com.epic.mychart',
    'com.cerner.healthelife',
    'com.goodrx',
    'com.cvs.pharmacy',
    'com.walgreens.android',
    'com.unitedhealth.uhc',
    'com.humana.mobile',
    'com.webmd.android',
    'com.oscarhealth',
    'com.ada.app',
    'com.fitbit.FitbitMobile',
    'com.samsung.android.wellbeing',
    'com.google.android.apps.fitness',
  };

  /// Friendly labels for known default packages
  static const Map<String, String> defaultAppNames = {
    // Banking
    'com.chase.sig.android': 'Chase Mobile',
    'com.bankofamerica.mft.mobile.banking': 'Bank of America',
    'com.wellsfargo.mobile': 'Wells Fargo',
    'com.citi.citimobile': 'Citi Mobile',
    'com.citibank.mobile.india': 'Citibank India',
    'com.phonepe.app': 'PhonePe',
    'net.one97.paytm': 'Paytm',
    'com.icicibank.mobile.banking': 'iMobile Pay (ICICI)',
    'com.sbi.lotusintouch': 'YONO SBI',
    'com.hdfcbank.payzapp': 'HDFC Bank',
    'com.axis.mobile': 'Axis Mobile',
    'com.paypal.android.p2pmobile': 'PayPal',
    'com.venmo': 'Venmo',
    'com.revolut.revolut': 'Revolut',
    'com.robinhood.android': 'Robinhood',
    'com.zerodha.kite3': 'Zerodha Kite',
    'com.nextbillion.groww': 'Groww',
    'com.capitalone.mobile.android': 'Capital One',
    'com.hsbc.hsbcuk': 'HSBC Mobile',
    'com.monzo.app': 'Monzo',
    // OTP
    'com.google.android.apps.authenticator2': 'Google Authenticator',
    'com.duosecurity.duomobile': 'Duo Mobile',
    'com.authy.authy': 'Authy',
    'com.azure.authenticator': 'Microsoft Authenticator',
    'com.microsoft.emmx': 'Microsoft Authenticator',
    'com.yubico.yubioath': 'Yubico Authenticator',
    'org.fedorahosted.freeotp': 'FreeOTP',
    'com.1password.1password': '1Password',
    'com.bitwarden.authenticator': 'Bitwarden Authenticator',
    // Health
    'com.myfitnesspal.android': 'MyFitnessPal',
    'com.practo.fabric': 'Practo',
    'com.1mg.myra': '1mg Healthcare',
    'com.myupchar': 'myUpchar Health',
    'com.teladoc.members': 'Teladoc',
    'com.epic.mychart': 'MyChart',
    'com.goodrx': 'GoodRx',
    'com.cvs.pharmacy': 'CVS Pharmacy',
    'com.walgreens.android': 'Walgreens',
    'com.webmd.android': 'WebMD',
    'com.ada.app': 'Ada Health',
    'com.fitbit.FitbitMobile': 'Fitbit',
    'com.google.android.apps.fitness': 'Google Fit',
  };

  /// Initialize and load saved exclusion toggles from DB
  Future<void> init() async {
    if (_initialized) return;
    if (_db != null) {
      try {
        final savedEntries = await _db.appExclusionsDao.getAll();
        for (final entry in savedEntries) {
          _customOverrides[entry.packageName] = entry.isExcluded;
          _customItems[entry.packageName] = AppExclusionItem(
            packageName: entry.packageName,
            appName: entry.appName ?? getFriendlyAppName(entry.packageName),
            category: entry.category ?? detectCategory(entry.packageName),
            isExcluded: entry.isExcluded,
            isDefaultSensitive: isDefaultSensitivePackage(entry.packageName),
            updatedAt: entry.updatedAt,
          );
        }
      } catch (e) {
        // Fallback silently
      }
    }
    _initialized = true;
    notifyListeners();
  }

  /// Evaluates whether a package is excluded.
  /// Execution speed is microsecond (<1ms) thanks to in-memory lookup.
  bool isExcluded(String packageName, {String? category}) {
    // 1. Check user custom override first
    if (_customOverrides.containsKey(packageName)) {
      return _customOverrides[packageName]!;
    }

    // 2. Fall back to pre-configured sensitive default rules
    return isDefaultSensitivePackage(packageName) || isDefaultSensitiveCategory(category);
  }

  /// Checks if package belongs to default sensitive packages (Banking, OTP, Health)
  static bool isDefaultSensitivePackage(String packageName) {
    if (defaultBankingPackages.contains(packageName) ||
        defaultOtpPackages.contains(packageName) ||
        defaultHealthPackages.contains(packageName)) {
      return true;
    }

    // Pattern matching for package naming conventions
    final lower = packageName.toLowerCase();
    if (lower.contains('.bank') ||
        lower.contains('banking') ||
        lower.contains('.authenticator') ||
        lower.contains('twofactor') ||
        lower.contains('.health') ||
        lower.contains('.medical') ||
        lower.contains('.pharmacy')) {
      return true;
    }

    return false;
  }

  /// Checks if category string represents a default sensitive category
  static bool isDefaultSensitiveCategory(String? category) {
    if (category == null) return false;
    final lower = category.toLowerCase().trim();
    return lower == 'banking' ||
        lower == 'finance' ||
        lower == 'otp' ||
        lower == '2fa' ||
        lower == 'authenticator' ||
        lower == 'healthcare' ||
        lower == 'health' ||
        lower == 'medical';
  }

  /// Detect category for a package
  static String detectCategory(String packageName, {String? defaultCategory}) {
    if (defaultCategory != null && isDefaultSensitiveCategory(defaultCategory)) {
      final lower = defaultCategory.toLowerCase();
      if (lower.contains('bank') || lower.contains('finance')) return 'banking';
      if (lower.contains('otp') || lower.contains('2fa') || lower.contains('auth')) return 'otp';
      if (lower.contains('health') || lower.contains('medical')) return 'health';
    }

    if (defaultBankingPackages.contains(packageName) ||
        packageName.toLowerCase().contains('.bank') ||
        packageName.toLowerCase().contains('banking')) {
      return 'banking';
    }
    if (defaultOtpPackages.contains(packageName) ||
        packageName.toLowerCase().contains('authenticator') ||
        packageName.toLowerCase().contains('2fa')) {
      return 'otp';
    }
    if (defaultHealthPackages.contains(packageName) ||
        packageName.toLowerCase().contains('health') ||
        packageName.toLowerCase().contains('medical') ||
        packageName.toLowerCase().contains('pharmacy')) {
      return 'health';
    }

    return 'general';
  }

  /// Get user friendly display name for an app package
  static String getFriendlyAppName(String packageName, {String? customName}) {
    if (customName != null && customName.isNotEmpty) return customName;
    if (defaultAppNames.containsKey(packageName)) {
      return defaultAppNames[packageName]!;
    }

    final parts = packageName.split('.');
    if (parts.length >= 2) {
      final namePart = parts.last == 'android' || parts.last == 'app'
          ? parts[parts.length - 2]
          : parts.last;
      return namePart
          .replaceAll('_', ' ')
          .replaceAll('-', ' ')
          .split(' ')
          .map((word) => word.isNotEmpty
              ? '${word[0].toUpperCase()}${word.substring(1)}'
              : '')
          .join(' ');
    }
    return packageName;
  }

  /// Updates an application's exclusion setting instantly and persists it to local DB.
  Future<void> setExclusion(
    String packageName,
    bool isExcluded, {
    String? appName,
    String? category,
  }) async {
    final name = appName ?? getFriendlyAppName(packageName);
    final cat = category ?? detectCategory(packageName);
    final now = DateTime.now();

    // 1. Instant in-memory state update
    _customOverrides[packageName] = isExcluded;
    _customItems[packageName] = AppExclusionItem(
      packageName: packageName,
      appName: name,
      category: cat,
      isExcluded: isExcluded,
      isDefaultSensitive: isDefaultSensitivePackage(packageName),
      updatedAt: now,
    );

    // 2. Persist to SQLite DB
    if (_db != null) {
      try {
        await _db.appExclusionsDao.upsertExclusion(AppExclusionEntry(
          packageName: packageName,
          appName: name,
          category: cat,
          isExcluded: isExcluded,
          isDefault: isDefaultSensitivePackage(packageName),
          updatedAt: now,
        ));
      } catch (e) {
        // Log/silently handle
      }
    }

    notifyListeners();
  }

  /// Resets all exclusion overrides to system pre-configured defaults.
  Future<void> resetToDefaults() async {
    _customOverrides.clear();
    _customItems.clear();

    if (_db != null) {
      try {
        await _db.appExclusionsDao.clearAll();
      } catch (_) {}
    }

    notifyListeners();
  }

  /// Returns a complete list of known apps including default sensitive apps,
  /// user customized apps, and apps seen in notifications.
  List<AppExclusionItem> getAllKnownApps({List<AppNotification>? notifications}) {
    final Map<String, AppExclusionItem> appMap = {};

    // 1. Add default sensitive packages
    for (final pkg in defaultBankingPackages) {
      appMap[pkg] = AppExclusionItem(
        packageName: pkg,
        appName: getFriendlyAppName(pkg),
        category: 'banking',
        isExcluded: isExcluded(pkg),
        isDefaultSensitive: true,
        updatedAt: DateTime.now(),
      );
    }
    for (final pkg in defaultOtpPackages) {
      appMap[pkg] = AppExclusionItem(
        packageName: pkg,
        appName: getFriendlyAppName(pkg),
        category: 'otp',
        isExcluded: isExcluded(pkg),
        isDefaultSensitive: true,
        updatedAt: DateTime.now(),
      );
    }
    for (final pkg in defaultHealthPackages) {
      appMap[pkg] = AppExclusionItem(
        packageName: pkg,
        appName: getFriendlyAppName(pkg),
        category: 'health',
        isExcluded: isExcluded(pkg),
        isDefaultSensitive: true,
        updatedAt: DateTime.now(),
      );
    }

    // 2. Add packages seen in active/stored notifications
    if (notifications != null) {
      for (final notif in notifications) {
        final pkg = notif.packageName;
        if (!appMap.containsKey(pkg)) {
          final cat = detectCategory(pkg, defaultCategory: notif.category);
          appMap[pkg] = AppExclusionItem(
            packageName: pkg,
            appName: getFriendlyAppName(pkg),
            category: cat,
            isExcluded: isExcluded(pkg, category: notif.category),
            isDefaultSensitive: isDefaultSensitivePackage(pkg) || isDefaultSensitiveCategory(notif.category),
            updatedAt: DateTime.now(),
          );
        }
      }
    }

    // 3. Apply custom user override items
    for (final entry in _customItems.entries) {
      final existing = appMap[entry.key];
      appMap[entry.key] = AppExclusionItem(
        packageName: entry.key,
        appName: entry.value.appName,
        category: entry.value.category.isNotEmpty ? entry.value.category : (existing?.category ?? detectCategory(entry.key)),
        isExcluded: entry.value.isExcluded,
        isDefaultSensitive: existing?.isDefaultSensitive ?? isDefaultSensitivePackage(entry.key),
        updatedAt: entry.value.updatedAt,
      );
    }

    final result = appMap.values.toList();
    // Sort sensitive apps first, then by app name
    result.sort((a, b) {
      if (a.isDefaultSensitive && !b.isDefaultSensitive) return -1;
      if (!a.isDefaultSensitive && b.isDefaultSensitive) return 1;
      return a.appName.compareTo(b.appName);
    });

    return result;
  }
}
