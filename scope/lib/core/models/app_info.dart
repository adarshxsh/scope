/// Lightweight data model representing installed applications on Android.
class AppInfo {
  final String packageName;
  final String appName;
  final bool isSystemApp;

  const AppInfo({
    required this.packageName,
    required this.appName,
    this.isSystemApp = false,
  });

  factory AppInfo.fromMap(Map<String, dynamic> map) {
    return AppInfo(
      packageName: map['packageName'] as String? ?? '',
      appName: map['appName'] as String? ?? map['packageName'] as String? ?? 'App',
      isSystemApp: map['isSystemApp'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'packageName': packageName,
      'appName': appName,
      'isSystemApp': isSystemApp,
    };
  }
}
