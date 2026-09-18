import 'package:flutter/foundation.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/models/notification_model.dart';

/// Centralized platform logging abstraction for Flutter.
///
/// Ensures raw notification titles and body content are replaced with
/// deterministic DJB2 hashes and structural metadata prior to log emission.
class HashedLogger {
  /// Computes deterministic DJB2 string hash matching Android native implementation.
  static int djb2(String val) {
    int hash = 5381;
    for (int i = 0; i < val.length; i++) {
      hash = ((hash << 5) + hash) + val.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Helper to get character length safely.
  static int charCount(String? val) => val?.length ?? 0;

  /// Logs Ghost AI inference report with structural metadata and hashes.
  static void logInferenceReport(AppNotification notification, GhostAIResult result) {
    final titleHash = djb2(notification.title);
    final titleLen = notification.title.length;
    final contentHash = djb2(notification.content);
    final contentLen = notification.content.length;
    final hasCategory = notification.category != null && notification.category!.isNotEmpty;

    final features = notification.extractedFeatures ?? {};
    final hasMoney = features['hasMoney'] == true || features['contains_money'] == true;
    final hasOtp = features['hasOtp'] == true || features['contains_otp'] == true;
    final hasLink = features['hasLink'] == true || features['contains_link'] == true;

    debugPrint('=== GHOST AI INFERENCE REPORT ===');
    debugPrint('Notification ID: ${notification.id}');
    debugPrint('Package: ${notification.packageName}');
    debugPrint('Title Hash: $titleHash (length: $titleLen)');
    debugPrint('Content Hash: $contentHash (length: $contentLen)');
    debugPrint('Metadata: category=${notification.category}, hasCategory=$hasCategory, isOngoing=${notification.isOngoing}');
    debugPrint('Entity Flags: hasMoney=$hasMoney, hasOtp=$hasOtp, hasLink=$hasLink');
    debugPrint('Feature Vector (First 15): ${result.featureVector.take(15).toList()}...');
    debugPrint('Inference Time: ${result.inferenceTimeUs} us');
    debugPrint('Raw Predicted Score: ${(result.predictedScore * 100).toStringAsFixed(2)}');
    debugPrint('Rule Score: ${result.ruleScore != null ? (result.ruleScore! * 100).toStringAsFixed(2) : "N/A"}');
    debugPrint('Final Fused Score: ${(result.reviewScore * 100).toStringAsFixed(2)}');
    debugPrint('==================================');
  }

  /// Logs a general notification event with structural metadata and hashes.
  static void logNotification(
    String tag,
    AppNotification notification, {
    String? event,
  }) {
    final titleHash = djb2(notification.title);
    final titleLen = notification.title.length;
    final contentHash = djb2(notification.content);
    final contentLen = notification.content.length;
    final prefix = event != null ? '[$event] ' : '';

    debugPrint(
      '[$tag] ${prefix}pkg=${notification.packageName}, id=${notification.id}, '
      'titleHash=$titleHash (len=$titleLen), contentHash=$contentHash (len=$contentLen)',
    );
  }

  /// Log wrappers for standard severity levels without raw payload text.
  static void logDebug(String tag, String message) {
    debugPrint('[$tag] [DEBUG] $message');
  }

  static void logInfo(String tag, String message) {
    debugPrint('[$tag] [INFO] $message');
  }

  static void logWarning(String tag, String message) {
    debugPrint('[$tag] [WARN] $message');
  }

  static void logError(String tag, String message, [dynamic error, StackTrace? stackTrace]) {
    final errStr = error != null ? ' Error: $error' : '';
    debugPrint('[$tag] [ERROR] $message$errStr');
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }
}
