import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/analysis/policy_engine.dart';
import 'package:scope/core/models/notification_model.dart';

/// Helper to build a minimal [AppNotification] for policy engine tests.
AppNotification _notif({
  String id = 'test-id',
  String packageName = 'com.example.app',
  String title = 'Test',
  String content = 'Test content',
  bool isOngoing = false,
}) {
  return AppNotification(
    id: id,
    packageName: packageName,
    title: title,
    content: content,
    timestamp: DateTime.now().millisecondsSinceEpoch,
    isOngoing: isOngoing,
  );
}

/// Helper to build a minimal [AnalysisResult] for policy engine tests.
AnalysisResult _result({String category = 'sys', double score = 0.5}) {
  return AnalysisResult(
    category: category,
    score: score,
    engineName: 'test',
    matchedSignals: [],
    latencyMs: 0,
  );
}

/// Helper to build [ExtractedFeatures] for policy engine tests.
ExtractedFeatures _features({
  String? otp,
  double? amount,
  bool hasDeadline = false,
}) {
  return ExtractedFeatures(
    otp: otp,
    amount: amount,
    hasDeadline: hasDeadline,
  );
}

void main() {
  group('PolicyEngine - Conservative Priority Resolution', () {
    // =========================================================================
    // Tightened score thresholds
    // =========================================================================
    group('Tightened score thresholds', () {
      test('score >= 0.90 maps to critical (before gates)', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(otp: '123456'), // OTP evidence for Critical gate
          notification: _notif(content: 'Your OTP is 123456'),
          lookAgainScore: 0.95,
        );
        expect(priority, equals('critical'));
      });

      test('score 0.80 no longer maps to critical (was 0.80, now 0.90)', () {
        // Without Critical evidence, 0.80 should NOT be critical
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(),
          lookAgainScore: 0.80,
        );
        expect(priority, isNot(equals('critical')));
      });

      test('score 0.50 maps to medium (was high at 0.50, now needs 0.70)', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(),
          lookAgainScore: 0.50,
        );
        expect(priority, equals('medium'));
      });

      test('score < 0.25 maps to low', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(),
          lookAgainScore: 0.10,
        );
        expect(priority, equals('low'));
      });
    });

    // =========================================================================
    // Media / Music ceiling
    // =========================================================================
    group('Media / Music ceiling', () {
      test('Spotify notification capped to low regardless of ML score', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(
            packageName: 'com.spotify.music',
            title: 'Spotify',
            content: 'Bohemian Rhapsody - Queen',
          ),
          lookAgainScore: 0.95,
        );
        expect(priority, equals('low'));
      });

      test('YouTube Music notification capped to low', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(
            packageName: 'com.google.android.apps.youtube.music',
            title: 'Now Playing',
            content: 'Shape of You - Ed Sheeran',
          ),
          lookAgainScore: 0.85,
        );
        expect(priority, equals('low'));
      });

      test('JioSaavn notification capped to low', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(
            packageName: 'com.jio.media.jiosaavn',
            title: 'JioSaavn',
            content: 'Playing: Latest Bollywood Hits',
          ),
          lookAgainScore: 0.70,
        );
        expect(priority, equals('low'));
      });

      test('"Now playing" content keyword caps any app to low', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(
            packageName: 'com.unknown.player',
            title: 'Now Playing',
            content: 'Some random track',
          ),
          lookAgainScore: 0.80,
        );
        expect(priority, equals('low'));
      });
    });

    // =========================================================================
    // Social media ceiling
    // =========================================================================
    group('Social media ceiling', () {
      test('Instagram "liked your photo" capped to low', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'social'),
          features: _features(),
          notification: _notif(
            packageName: 'com.instagram.android',
            title: 'Instagram',
            content: 'john_doe liked your photo',
          ),
          lookAgainScore: 0.60,
        );
        expect(priority, equals('low'));
      });

      test('Facebook "commented on your post" capped to low', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'social'),
          features: _features(),
          notification: _notif(
            packageName: 'com.facebook.katana',
            title: 'Facebook',
            content: 'Jane commented on your post',
          ),
          lookAgainScore: 0.75,
        );
        expect(priority, equals('low'));
      });

      test('Twitter "new follower" capped to low', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'social'),
          features: _features(),
          notification: _notif(
            packageName: 'com.twitter.android',
            title: 'Twitter',
            content: 'You have a new follower',
          ),
          lookAgainScore: 0.40,
        );
        expect(priority, equals('low'));
      });

      test('Instagram DM preserved at high (not demoted)', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'msg'),
          features: _features(),
          notification: _notif(
            packageName: 'com.instagram.android',
            title: 'John',
            content: 'sent you a message',
          ),
          lookAgainScore: 0.75,
        );
        expect(priority, equals('high'));
      });

      test('Instagram DM never becomes critical', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'msg'),
          features: _features(),
          notification: _notif(
            packageName: 'com.instagram.android',
            title: 'John',
            content: 'sent you a message',
          ),
          lookAgainScore: 0.99,
        );
        // Social DM cap at high, then High gate checks msg category → preserved
        expect(priority, equals('high'));
      });

      test('Instagram "mentioned you" preserved (not demoted to low)', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'msg'),
          features: _features(),
          notification: _notif(
            packageName: 'com.instagram.android',
            title: 'Instagram',
            content: '@adarsh mentioned you in a comment',
          ),
          lookAgainScore: 0.75,
        );
        // DM path preserves up to high
        expect(priority, isNot(equals('low')));
      });

      test('LinkedIn "suggested for you" capped to low', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'social'),
          features: _features(),
          notification: _notif(
            packageName: 'com.linkedin.android',
            title: 'LinkedIn',
            content: 'Jobs suggested for you',
          ),
          lookAgainScore: 0.55,
        );
        expect(priority, equals('low'));
      });
    });

    // =========================================================================
    // Entertainment ceiling
    // =========================================================================
    group('Entertainment ceiling', () {
      test('YouTube recommendation capped to low', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'social'),
          features: _features(),
          notification: _notif(
            packageName: 'com.google.android.youtube',
            title: 'YouTube',
            content: 'New video from MrBeast',
          ),
          lookAgainScore: 0.55,
        );
        expect(priority, equals('low'));
      });

      test('Netflix "continue watching" capped to low', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(
            packageName: 'com.netflix.mediaclient',
            title: 'Netflix',
            content: 'Continue watching Stranger Things',
          ),
          lookAgainScore: 0.80,
        );
        expect(priority, equals('low'));
      });

      test('Twitch stream notification capped to low', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(
            packageName: 'tv.twitch.android.app',
            title: 'Twitch',
            content: 'Streamer123 is now live',
          ),
          lookAgainScore: 0.60,
        );
        expect(priority, equals('low'));
      });

      test('"Recommended for you" keyword caps any app to low', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(
            packageName: 'com.unknown.app',
            title: 'App',
            content: 'Recommended for you: Top 10 things',
          ),
          lookAgainScore: 0.80,
        );
        expect(priority, equals('low'));
      });
    });

    // =========================================================================
    // Promotional ceiling
    // =========================================================================
    group('Promotional ceiling', () {
      test('Amazon shopping offer capped to low', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'promo'),
          features: _features(),
          notification: _notif(
            packageName: 'com.amazon.mShop.android.shopping',
            title: 'Amazon',
            content: '50% off on electronics!',
          ),
          lookAgainScore: 0.60,
        );
        expect(priority, equals('low'));
      });

      test('Swiggy promo capped to low', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'promo'),
          features: _features(),
          notification: _notif(
            packageName: 'in.swiggy.android',
            title: 'Swiggy',
            content: 'Use code SAVE50 for cashback!',
          ),
          lookAgainScore: 0.45,
        );
        expect(priority, equals('low'));
      });

      test('"Flash sale" keyword caps any app to low', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'promo'),
          features: _features(),
          notification: _notif(
            packageName: 'com.unknown.shop',
            title: 'Shop',
            content: 'Flash sale starting now! Grab deals.',
          ),
          lookAgainScore: 0.70,
        );
        expect(priority, equals('low'));
      });
    });

    // =========================================================================
    // Critical whitelist gate
    // =========================================================================
    group('Critical whitelist gate', () {
      test('OTP notification stays critical', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(otp: '482916'),
          notification: _notif(
            packageName: 'com.whatsapp',
            title: 'WhatsApp',
            content: 'Your OTP is 482916',
          ),
          lookAgainScore: 0.95,
        );
        expect(priority, equals('critical'));
      });

      test('Banking fraud alert stays critical', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'finance'),
          features: _features(amount: 5000.0),
          notification: _notif(
            packageName: 'com.hdfc.mobilebanking',
            title: 'HDFC Alert',
            content: 'Rs. 5000 debited. If unauthorized, call immediately.',
          ),
          lookAgainScore: 0.92,
        );
        expect(priority, equals('critical'));
      });

      test('Security alert stays critical', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(
            packageName: 'com.google.android.gms',
            title: 'Google',
            content: 'Security alert: Unusual sign-in from a new device',
          ),
          lookAgainScore: 0.95,
        );
        expect(priority, equals('critical'));
      });

      test('Emergency alert stays critical', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(
            packageName: 'android',
            title: 'Emergency Alert',
            content: 'Severe weather warning in your area',
          ),
          lookAgainScore: 0.95,
        );
        expect(priority, equals('critical'));
      });

      test('Generic high-score notification downgraded from critical', () {
        // High ML score but no critical evidence → should NOT be critical
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(
            packageName: 'com.example.app',
            title: 'App Update',
            content: 'Version 2.0 is available',
          ),
          lookAgainScore: 0.95,
        );
        expect(priority, isNot(equals('critical')));
      });

      test('Payment failed stays critical', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'finance'),
          features: _features(),
          notification: _notif(
            packageName: 'com.phonepe.app',
            title: 'PhonePe',
            content: 'Payment failed for order #12345',
          ),
          lookAgainScore: 0.92,
        );
        expect(priority, equals('critical'));
      });
    });

    // =========================================================================
    // High whitelist gate
    // =========================================================================
    group('High whitelist gate', () {
      test('Meeting reminder stays high', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(
            packageName: 'com.google.android.calendar',
            title: 'Calendar',
            content: 'Meeting in 15 minutes: Sprint Planning',
          ),
          lookAgainScore: 0.75,
        );
        expect(priority, equals('high'));
      });

      test('WhatsApp message (msg category) stays high', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'msg'),
          features: _features(),
          notification: _notif(
            packageName: 'com.whatsapp',
            title: 'Mom',
            content: 'Where are you?',
          ),
          lookAgainScore: 0.75,
        );
        expect(priority, equals('high'));
      });

      test('Email stays high', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'email'),
          features: _features(),
          notification: _notif(
            packageName: 'com.google.android.gm',
            title: 'GSoC Team',
            content: 'Your proposal has been reviewed',
          ),
          lookAgainScore: 0.75,
        );
        expect(priority, equals('high'));
      });

      test('Health appointment stays high', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'health'),
          features: _features(),
          notification: _notif(
            packageName: 'com.apollo.patientapp',
            title: 'Apollo',
            content: 'Your appointment is tomorrow at 10 AM',
          ),
          lookAgainScore: 0.75,
        );
        expect(priority, equals('high'));
      });

      test('Generic app notification downgraded from high to medium', () {
        // High ML score but no High evidence → demoted to medium
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(
            packageName: 'com.example.app',
            title: 'App',
            content: 'Your weekly report is ready',
          ),
          lookAgainScore: 0.75,
        );
        expect(priority, equals('medium'));
      });

      test('Package delivery notification stays high', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(
            packageName: 'com.delhivery.app',
            title: 'Delhivery',
            content: 'Your package is arriving today',
          ),
          lookAgainScore: 0.75,
        );
        expect(priority, equals('high'));
      });

      test('Ongoing notification (msg category) NOT promoted to high', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'msg'),
          features: _features(),
          notification: _notif(
            packageName: 'com.whatsapp',
            title: 'WhatsApp',
            content: 'WhatsApp Web is active',
            isOngoing: true,
          ),
          lookAgainScore: 0.75,
        );
        // msg + isOngoing → High gate fails for msg → demoted to medium
        expect(priority, equals('medium'));
      });
    });

    // =========================================================================
    // Conservative merge (score + category)
    // =========================================================================
    group('Conservative merge', () {
      test('category evidence promotes even low ML score for finance', () {
        // Score says low, but category (finance) warrants high
        // Category promotion kicks in → high
        // High gate: category == finance → stays high
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'finance'),
          features: _features(),
          notification: _notif(packageName: 'com.hdfc.mobilebanking'),
          lookAgainScore: 0.10,
        );
        expect(priority, equals('high'));
      });

      test('low category overrides high score', () {
        // Score says high, category (promo) says low → result is low
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'promo'),
          features: _features(),
          notification: _notif(),
          lookAgainScore: 0.80,
        );
        expect(priority, equals('low'));
      });

      test('null lookAgainScore uses category priority for promotion', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'finance'),
          features: _features(amount: 5000.0),
          notification: _notif(
            packageName: 'com.hdfc.mobilebanking',
            title: 'HDFC',
            content: 'Rs. 5000 debited from your account',
          ),
          lookAgainScore: null,
        );
        // Score is null → medium, but category says critical (finance + amount)
        // Category promotion kicks in → critical
        // Critical gate: amount != null → stays critical
        expect(priority, equals('critical'));
      });
    });

    // =========================================================================
    // End-to-end scenarios (Before → After)
    // =========================================================================
    group('End-to-end before/after scenarios', () {
      test('Spotify + high ML → Low (was Critical)', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(
            packageName: 'com.spotify.music',
            title: 'Spotify',
            content: 'Bohemian Rhapsody - Queen',
          ),
          lookAgainScore: 0.85,
        );
        expect(priority, equals('low'));
      });

      test('Instagram like + moderate ML → Low (was High)', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'social'),
          features: _features(),
          notification: _notif(
            packageName: 'com.instagram.android',
            title: 'Instagram',
            content: 'john_doe liked your photo',
          ),
          lookAgainScore: 0.60,
        );
        expect(priority, equals('low'));
      });

      test('YouTube video + high ML → Low (was High)', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'social'),
          features: _features(),
          notification: _notif(
            packageName: 'com.google.android.youtube',
            title: 'YouTube',
            content: 'New video from MrBeast',
          ),
          lookAgainScore: 0.55,
        );
        expect(priority, equals('low'));
      });

      test('OTP + very high ML → Critical (preserved)', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(otp: '482916'),
          notification: _notif(
            packageName: 'com.whatsapp',
            title: 'WhatsApp',
            content: 'Your OTP is 482916',
          ),
          lookAgainScore: 0.95,
        );
        expect(priority, equals('critical'));
      });

      test('Bank debit + high ML → Critical (preserved)', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'finance'),
          features: _features(amount: 5000.0),
          notification: _notif(
            packageName: 'com.hdfc.mobilebanking',
            title: 'HDFC Alert',
            content: 'Rs. 5000 debited from A/C ending 1234',
          ),
          lookAgainScore: 0.92,
        );
        expect(priority, equals('critical'));
      });

      test('Calendar meeting → High (preserved)', () {
        final priority = PolicyEngine.resolvePriority(
          fusedResult: _result(category: 'sys'),
          features: _features(),
          notification: _notif(
            packageName: 'com.google.android.calendar',
            title: 'Calendar',
            content: 'Standup starts in 5 minutes',
          ),
          lookAgainScore: 0.75,
        );
        expect(priority, equals('high'));
      });
    });
  });
}
