import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/models/notification_model.dart';

/// Represents a single model feature's influence on priority classification.
class FeatureAttribution {
  /// Unique key for the feature (e.g. 'contains_otp', 'contains_amount').
  final String featureKey;

  /// Display name of the feature (e.g. 'Verification Code').
  final String featureName;

  /// Numerical weight/influence delta (-1.0 to +1.0).
  final double influence;

  /// Qualitative impact ('positive', 'negative', 'neutral').
  final String impact;

  /// Human-readable explanation of how this feature influenced the priority score.
  final String description;

  const FeatureAttribution({
    required this.featureKey,
    required this.featureName,
    required this.influence,
    required this.impact,
    required this.description,
  });

  Map<String, dynamic> toMap() => {
        'featureKey': featureKey,
        'featureName': featureName,
        'influence': influence,
        'impact': impact,
        'description': description,
      };

  factory FeatureAttribution.fromMap(Map<String, dynamic> map) {
    final rawInfluence = (map['influence'] as num?)?.toDouble() ?? 0.0;
    final sanitizedInfluence = rawInfluence.isFinite ? rawInfluence : 0.0;
    return FeatureAttribution(
      featureKey: map['featureKey'] as String? ?? 'unknown',
      featureName: map['featureName'] as String? ?? 'Feature',
      influence: sanitizedInfluence,
      impact: map['impact'] as String? ?? 'neutral',
      description: map['description'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'FeatureAttribution($featureKey: ${influence >= 0 ? "+" : ""}${(influence * 100).toStringAsFixed(0)}%, $impact)';
}

/// Calculates feature attribution weight influences for a given notification and its features.
class FeatureAttributionCalculator {
  /// Redacts sensitive verification codes, phone numbers, and raw financial digits from text.
  static String sanitizeText(String input) {
    if (input.isEmpty) return input;
    String result = input;
    // 1. Redact phone numbers
    result = result.replaceAll(RegExp(r'\b(?:\+\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b'), '[REDACTED_PHONE]');
    // 2. Redact emails
    result = result.replaceAll(RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'), '[REDACTED_EMAIL]');
    // 3. Redact OTPs / verification numbers
    result = result.replaceAll(RegExp(r'\b\d{4,8}\b'), '[REDACTED_CODE]');
    return result;
  }

  /// Calculates feature attributions for a given notification.
  static List<FeatureAttribution> computeAttributions({
    required AppNotification notification,
    required ExtractedFeatures features,
    double? predictedScore,
    String? matchedRuleId,
  }) {
    final attributions = <FeatureAttribution>[];

    // 1. OTP Code Attribution
    if (features.otp != null || notification.content.toLowerCase().contains('otp') || notification.content.toLowerCase().contains('code')) {
      attributions.add(
        const FeatureAttribution(
          featureKey: 'contains_otp',
          featureName: 'Authentication Security Code',
          influence: 0.65,
          impact: 'positive',
          description: 'Elevated priority due to time-sensitive verification code.',
        ),
      );
    }

    // 2. Financial Transaction / Amount Attribution
    if (features.amount != null) {
      final amountVal = features.amount!;
      final formattedAmount = amountVal.isFinite ? '₹${amountVal.toStringAsFixed(0)}' : 'Detected';
      attributions.add(
        FeatureAttribution(
          featureKey: 'contains_amount',
          featureName: 'Financial Transaction Amount',
          influence: 0.45,
          impact: 'positive',
          description: 'Recognized payment/debit quantity ($formattedAmount).',
        ),
      );
    } else if (notification.packageName.contains('bank') || notification.packageName.contains('pay') || notification.content.toLowerCase().contains('debit') || notification.content.toLowerCase().contains('payment')) {
      attributions.add(
        const FeatureAttribution(
          featureKey: 'contains_payment_keywords',
          featureName: 'Financial Service Signal',
          influence: 0.35,
          impact: 'positive',
          description: 'Identified financial institution or payment channel.',
        ),
      );
    }

    // 3. Deadline & Time Sensitivity
    if (features.hasDeadline) {
      attributions.add(
        const FeatureAttribution(
          featureKey: 'contains_deadline',
          featureName: 'Time Sensitivity / Deadline',
          influence: 0.40,
          impact: 'positive',
          description: 'Urgent timing keywords detected in message body.',
        ),
      );
    }

    // 4. Official Source / Government Channel
    if (notification.packageName.contains('gov') || notification.packageName.contains('passport') || notification.packageName.contains('digilocker')) {
      attributions.add(
        const FeatureAttribution(
          featureKey: 'official_source',
          featureName: 'Official Institutional Channel',
          influence: 0.30,
          impact: 'positive',
          description: 'Sent by authenticated government or public administrative portal.',
        ),
      );
    }

    // 5. Rule Engine Match Influence
    if (matchedRuleId != null && matchedRuleId.isNotEmpty) {
      attributions.add(
        FeatureAttribution(
          featureKey: 'rule_match',
          featureName: 'System Rule Match',
          influence: 0.50,
          impact: 'positive',
          description: 'Matched deterministic rule criteria ($matchedRuleId).',
        ),
      );
    }

    // 6. Promotional / Low Priority Penalty
    final lowerTitle = notification.title.toLowerCase();
    final lowerContent = notification.content.toLowerCase();
    final isPromo = lowerTitle.contains('off') ||
        lowerTitle.contains('deal') ||
        lowerTitle.contains('discount') ||
        lowerContent.contains('buy today') ||
        lowerContent.contains('free') ||
        lowerContent.contains('sale');

    if (isPromo) {
      attributions.add(
        const FeatureAttribution(
          featureKey: 'promo_keywords',
          featureName: 'Promotional Signal',
          influence: -0.45,
          impact: 'negative',
          description: 'Suppressed priority due to marketing or promotional phrasing.',
        ),
      );
    }

    // 7. General Social / Messaging Channel
    if (notification.packageName.contains('whatsapp') || notification.packageName.contains('telegram') || notification.packageName.contains('messenger')) {
      if (attributions.isEmpty) {
        attributions.add(
          const FeatureAttribution(
            featureKey: 'messaging_channel',
            featureName: 'Personal Messaging Channel',
            influence: 0.15,
            impact: 'positive',
            description: 'Direct personal communication channel.',
          ),
        );
      }
    }

    // Default neutral attribution if empty
    if (attributions.isEmpty) {
      attributions.add(
        const FeatureAttribution(
          featureKey: 'ambient_content',
          featureName: 'Standard Ambient Context',
          influence: 0.0,
          impact: 'neutral',
          description: 'Standard ambient notification text with no strong priority signals.',
        ),
      );
    }

    return attributions;
  }
}
