import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scope/core/bridge/notification_bridge.dart';

/// Service managing user-configured app exclusions.
class AppExclusionService extends ChangeNotifier {
  final NotificationBridge _bridge;
  final Set<String> _excludedPackages = {};
  bool _initialized = false;

  AppExclusionService({NotificationBridge? bridge})
      : _bridge = bridge ?? NotificationBridge();

  Set<String> get excludedPackages => Set.unmodifiable(_excludedPackages);

  /// Default suggested popular apps for quick exclusion controls.
  static const List<Map<String, String>> popularAppsToExclude = [
    {'name': 'WhatsApp', 'package': 'com.whatsapp'},
    {'name': 'Instagram', 'package': 'com.instagram.android'},
    {'name': 'Facebook', 'package': 'com.facebook.katana'},
    {'name': 'Snapchat', 'package': 'com.snapchat.android'},
    {'name': 'System UI', 'package': 'com.android.systemui'},
  ];

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final loaded = await _loadFromStorage();
      _excludedPackages.addAll(loaded);
      await _syncWithBridge();
    } catch (e) {
      debugPrint('AppExclusionService initialize error: $e');
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  bool isPackageExcluded(String packageName) {
    final pkg = packageName.trim().toLowerCase();
    if (pkg.isEmpty) return false;
    if (pkg == 'com.scope.attentions' || pkg == 'com.scope.attentionos') {
      return true;
    }
    return _excludedPackages.any((p) => p.toLowerCase() == pkg);
  }

  Future<void> addExcludedPackage(String packageName) async {
    final trimmed = packageName.trim();
    if (trimmed.isEmpty) return;
    if (_excludedPackages.add(trimmed)) {
      await _saveAndSync();
      notifyListeners();
    }
  }

  Future<void> removeExcludedPackage(String packageName) async {
    final trimmed = packageName.trim().toLowerCase();
    final beforeCount = _excludedPackages.length;
    _excludedPackages.removeWhere((p) => p.trim().toLowerCase() == trimmed);
    if (_excludedPackages.length < beforeCount) {
      await _saveAndSync();
      notifyListeners();
    }
  }

  Future<void> togglePackageExcluded(String packageName) async {
    if (isPackageExcluded(packageName)) {
      await removeExcludedPackage(packageName);
    } else {
      await addExcludedPackage(packageName);
    }
  }

  Future<void> setExcludedPackages(List<String> packages) async {
    _excludedPackages.clear();
    for (final p in packages) {
      if (p.trim().isNotEmpty) {
        _excludedPackages.add(p.trim());
      }
    }
    await _saveAndSync();
    notifyListeners();
  }

  Future<void> _saveAndSync() async {
    await _saveToStorage();
    await _syncWithBridge();
  }

  Future<void> _syncWithBridge() async {
    try {
      await _bridge.setExcludedPackages(_excludedPackages.toList());
    } catch (_) {
      // Ignore channel bridge errors in non-Android or test environments
    }
  }

  Future<File?> _getStorageFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/excluded_apps.json');
    } catch (e) {
      // In test or non-supported platform environment
      return null;
    }
  }

  Future<List<String>> _loadFromStorage() async {
    try {
      final file = await _getStorageFile();
      if (file == null || !await file.exists()) return [];
      final contents = await file.readAsString();
      final decoded = jsonDecode(contents);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (e) {
      debugPrint('Failed to load excluded apps from storage: $e');
    }
    return [];
  }

  Future<void> _saveToStorage() async {
    try {
      final file = await _getStorageFile();
      if (file == null) return;
      await file.writeAsString(jsonEncode(_excludedPackages.toList()));
    } catch (e) {
      debugPrint('Failed to save excluded apps to storage: $e');
    }
  }
}
