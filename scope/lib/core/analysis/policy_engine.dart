import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/models/notification_model.dart';

/// Resolves business priority level from semantic classification and features.
class PolicyEngine {
  /// Evaluates the fused semantic analysis and extracted features,
  /// determining the final priority tier ('critical', 'high', 'medium', 'low').
  static String resolvePriority({
    required AnalysisResult fusedResult,
    required ExtractedFeatures features,
    required AppNotification notification,
  }) {
    final category = fusedResult.category;

    // 1. Critical Priority Tier
    // - Finance Category + Transaction Amount parsed (bank debits/charges)
    if (category == 'finance' && features.amount != null) {
      return 'critical';
    }
    // - Security alerts containing OTP verification codes
    if (features.otp != null) {
      return 'critical';
    }
    // - Scholarship deadlines or crucial portal updates ending soon
    if (category == 'scholarship' && features.hasDeadline) {
      return 'critical';
    }

    // 2. High Priority Tier
    // - General finance category notifications (balance warnings without amounts)
    if (category == 'finance') {
      return 'high';
    }
    // - Health and medical reminders/appointments
    if (category == 'health') {
      return 'high';
    }
    // - Direct personal messaging channels (WhatsApp, Slack)
    if (category == 'msg' && !notification.isOngoing) {
      return 'high';
    }
    // - Direct emails (e.g. GSOC updates)
    if (category == 'email' && !notification.isOngoing) {
      return 'high';
    }

    // 3. Low Priority Tier
    // - Marketing, shopping promo alerts
    if (category == 'promo') {
      return 'low';
    }
    // - Social network likes, comments, stories
    if (category == 'social') {
      return 'low';
    }

    // 4. Default Tier
    return 'medium';
  }
}
