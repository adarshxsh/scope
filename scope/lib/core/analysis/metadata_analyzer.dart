import 'package:scope/core/models/notification_model.dart';

/// Analyzes notification metadata such as package name categories.
class MetadataAnalyzer {
  /// Map of known package names to their semantic category hints.
  static const Map<String, String> packageCategoryMap = {
    'com.whatsapp': 'msg',
    'com.slack': 'msg',
    'org.telegram.messenger': 'msg',
    'com.google.android.gm': 'email',
    'com.microsoft.office.outlook': 'email',
    'com.instagram.android': 'social',
    'com.facebook.katana': 'social',
    'com.twitter.android': 'social',
    'com.zhiliaoapp.musically': 'social',
    'com.amazon.mShop.android.shopping': 'promo',
    'com.swiggy': 'promo',
    'com.zomato': 'promo',
    'com.hdfc.mobilebanking': 'finance',
    'com.icici.mobilebanking': 'finance',
    'com.apollo.patientapp': 'health',
    'in.gov.scholarships': 'scholarship',
    'android': 'sys',
  };

  /// Resolves the category hint from the package name of the notification.
  static String? getCategoryHint(AppNotification notification) {
    return packageCategoryMap[notification.packageName];
  }

  /// Evaluates metadata signals.
  /// For instance, determines if a notification is low priority purely based on metadata,
  /// e.g. ongoing downloads or persistent media players.
  static bool isSystemOngoing(AppNotification notification) {
    return notification.isOngoing && notification.packageName == 'android';
  }
}
