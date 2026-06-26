/// Test data generator for simulating different notification types.
///
/// Generates realistic [AppNotification] objects directly in Dart,
/// bypassing the Android notification system entirely.
/// This avoids the Android limitation where NotificationListenerService
/// cannot capture notifications from its own app.
library;

import 'package:scope/core/models/notification_model.dart';

/// Generates a batch of realistic test notifications covering all
/// major categories: message, email, chat, social, promo, finance,
/// health, news, system, and scholarship/deadline alerts.
class TestNotificationGenerator {
  int _idCounter = 0;

  String _nextId() => 'test_${++_idCounter}_${DateTime.now().millisecondsSinceEpoch}';

  /// Generate all test notification types at once.
  List<AppNotification> generateAll() {
    return [
      _message(),
      _email(),
      _chat(),
      _social(),
      _promo(),
      _finance(),
      _health(),
      _news(),
      _system(),
      _scholarship(),
    ];
  }

  /// Generate a specific type by name.
  /// Returns null if type is not recognized.
  AppNotification? generateByType(String type) {
    return switch (type) {
      'message' => _message(),
      'email' => _email(),
      'chat' => _chat(),
      'social' => _social(),
      'promo' => _promo(),
      'finance' => _finance(),
      'health' => _health(),
      'news' => _news(),
      'system' => _system(),
      'scholarship' => _scholarship(),
      _ => null,
    };
  }

  /// All available test notification types.
  static const List<String> availableTypes = [
    'message',
    'email',
    'chat',
    'social',
    'promo',
    'finance',
    'health',
    'news',
    'system',
    'scholarship',
  ];

  // --- Individual notification types ---

  AppNotification _message() => AppNotification(
        id: _nextId(),
        packageName: 'com.whatsapp',
        title: 'Mom',
        content:
            "Don't forget to take your medicine at 9 PM tonight. "
            "Also, grandma called and asked about you. She wants to know "
            "if you're coming for dinner this Sunday.",
        timestamp: DateTime.now().millisecondsSinceEpoch,
        category: 'msg',
        isOngoing: false,
      );

  AppNotification _email() => AppNotification(
        id: _nextId(),
        packageName: 'com.google.android.gm',
        title: 'Google Summer of Code - Application Update',
        content:
            "Congratulations! Your proposal for GSoC 2026 has been accepted. "
            "Please review the next steps and mentor assignment details. "
            "You have 48 hours to confirm your participation.",
        timestamp: DateTime.now().millisecondsSinceEpoch - 60000,
        category: 'email',
        isOngoing: false,
      );

  AppNotification _chat() => AppNotification(
        id: _nextId(),
        packageName: 'com.slack',
        title: 'Dev Team - Slack',
        content:
            "@adarsh the PR is ready for review. Can you check the notification "
            "listener changes before EOD? Also, standup moved to 3 PM today.",
        timestamp: DateTime.now().millisecondsSinceEpoch - 120000,
        category: 'msg',
        isOngoing: false,
      );

  AppNotification _social() => AppNotification(
        id: _nextId(),
        packageName: 'com.instagram.android',
        title: 'Instagram',
        content: 'coding_wizard and 42 others liked your photo.',
        timestamp: DateTime.now().millisecondsSinceEpoch - 300000,
        category: 'social',
        isOngoing: false,
      );

  AppNotification _promo() => AppNotification(
        id: _nextId(),
        packageName: 'com.amazon.mShop.android.shopping',
        title: 'Amazon - Flash Sale!',
        content:
            '🔥 50% off on electronics! Limited time offer ends in 2 hours. Shop now!',
        timestamp: DateTime.now().millisecondsSinceEpoch - 600000,
        category: 'promo',
        isOngoing: false,
      );

  AppNotification _finance() => AppNotification(
        id: _nextId(),
        packageName: 'com.hdfc.mobilebanking',
        title: 'HDFC Bank Alert',
        content:
            "Rs. 15,000 debited from A/c XX4523 on 26-Jun-2026. "
            "UPI Ref: 428715693254. Available balance: Rs. 23,450. "
            "If not done by you, call 1800-XXX-XXXX immediately to block your account.",
        timestamp: DateTime.now().millisecondsSinceEpoch - 30000,
        category: 'alarm',
        isOngoing: false,
      );

  AppNotification _health() => AppNotification(
        id: _nextId(),
        packageName: 'com.apollo.patientapp',
        title: 'Apollo Hospital - Appointment Reminder',
        content:
            "Your appointment with Dr. Sharma (Cardiology) is tomorrow at 10:30 AM. "
            "Location: Apollo Hospital, Jubilee Hills. Please carry your previous "
            "reports and insurance card. Fasting required for blood test.",
        timestamp: DateTime.now().millisecondsSinceEpoch - 180000,
        category: 'reminder',
        isOngoing: false,
      );

  AppNotification _news() => AppNotification(
        id: _nextId(),
        packageName: 'com.google.android.apps.magazines',
        title: 'Google News - Breaking',
        content:
            "India launches new AI-powered satellite for weather prediction. "
            "The satellite, named 'Meghdoot-2', will improve monsoon forecasting "
            "accuracy by 40% and help farmers with crop planning.",
        timestamp: DateTime.now().millisecondsSinceEpoch - 900000,
        category: 'recommendation',
        isOngoing: false,
      );

  AppNotification _system() => AppNotification(
        id: _nextId(),
        packageName: 'android',
        title: 'System Update Available',
        content:
            "Android 16 security patch is available. Tap to download (125 MB). "
            "Your device will restart during installation.",
        timestamp: DateTime.now().millisecondsSinceEpoch - 1800000,
        category: 'sys',
        isOngoing: true,
      );

  AppNotification _scholarship() => AppNotification(
        id: _nextId(),
        packageName: 'in.gov.scholarships',
        title: 'National Scholarship Portal',
        content:
            "⚠️ DEADLINE ALERT: Post-Matric Scholarship application closes in 3 days! "
            "Apply before June 30th to receive Rs. 50,000/year. "
            "Required docs: Aadhaar, income certificate, mark sheets. "
            "Visit scholarships.gov.in to apply now.",
        timestamp: DateTime.now().millisecondsSinceEpoch - 15000,
        category: 'reminder',
        isOngoing: false,
      );
}
