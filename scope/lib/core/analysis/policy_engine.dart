import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/models/notification_model.dart';

/// Resolves business priority level from semantic classification and features.
///
/// The policy engine acts as the final authority after ML inference and score
/// fusion. It applies deterministic ceiling rules and whitelist gates to ensure
/// that High and Critical priorities are rare and reserved for genuinely urgent
/// notifications. The engine can downgrade aggressive ML predictions but never
/// upgrades beyond what the evidence supports.
class PolicyEngine {
  // ---------------------------------------------------------------------------
  // Priority ordering (lower index = lower priority)
  // ---------------------------------------------------------------------------
  static const _priorityOrder = ['low', 'medium', 'high', 'critical'];

  // ---------------------------------------------------------------------------
  // Package fragment lists for deterministic ceiling rules.
  //
  // A notification's packageName is checked with `contains()` against these
  // fragments (all lowercase). This avoids brittle exact-match logic and
  // handles regional variants (e.g. "com.spotify.music", "com.spotify.lite").
  // ---------------------------------------------------------------------------

  /// Music and media player packages — ceiling: low.
  static const _mediaPackages = [
    'spotify',
    'youtube.music',
    'youtubemusic',
    'apple.music',
    'vlc',
    'mxplayer',
    'mx.player',
    'poweramp',
    'amazon.music',
    'jiosaavn',
    'wynk',
    'gaana',
    'musicplayer',
    'music.player',
    'shazam',
    'soundcloud',
    'bandcamp',
    'deezer',
    'tidal',
  ];

  /// Public social media packages — ceiling: low (except DMs/mentions).
  static const _socialPackages = [
    'instagram',
    'facebook.katana',
    'facebook.lite',
    'twitter',
    'snapchat',
    'reddit',
    'tumblr',
    'pinterest',
    'linkedin',
    'tiktok',
    'musically',
    'threads',
  ];

  /// Entertainment and streaming packages — ceiling: low.
  static const _entertainmentPackages = [
    'youtube',
    'netflix',
    'primevideo',
    'prime.video',
    'twitch',
    'podcast',
    'hotstar',
    'voot',
    'zee5',
    'sonyliv',
    'jiocinema',
    'mxplayer',
    'mx.player',
    'disney',
  ];

  /// Promotional and shopping packages — ceiling: low.
  static const _promoPackages = [
    'amazon.mshop',
    'amazon.shopping',
    'flipkart',
    'myntra',
    'meesho',
    'ajio',
    'swiggy',
    'zomato',
    'blinkit',
    'zepto',
    'dunzo',
    'cred',
    'paytm.mall',
    'nykaa',
  ];

  // ---------------------------------------------------------------------------
  // Content keyword lists for deterministic demotion rules.
  // Matched via `toLowerCase().contains()` against title + content.
  // ---------------------------------------------------------------------------

  /// Social engagement keywords — ceiling: low.
  static const _socialEngagementKeywords = [
    'liked your',
    'liked a',
    'followed you',
    'commented on',
    'reacted to',
    'story',
    'tagged you',
    'new follower',
    'suggested for you',
    'suggested friend',
    'suggested post',
    'trending',
    'memories',
    'highlights',
    'community update',
    'people you may know',
    'new connection',
  ];

  /// Media playback keywords — ceiling: low.
  static const _mediaPlaybackKeywords = [
    'now playing',
    'next track',
    'currently playing',
    'playlist',
    'playing:',
    'paused:',
    'listening to',
  ];

  /// Entertainment recommendation keywords — ceiling: low.
  static const _entertainmentRecoKeywords = [
    'recommended for you',
    'because you watched',
    'new episode',
    'continue watching',
    'trending now',
    'top picks',
    'watch now',
    'new release',
    'just added',
  ];

  /// Promotional content keywords — ceiling: low.
  static const _promoContentKeywords = [
    '% off',
    'cashback',
    'coupon',
    'flash sale',
    'limited time',
    'shop now',
    'deal of',
    'use code',
    'referral',
    'earn reward',
    'free delivery',
    'buy now',
    'exclusive offer',
    'promo code',
  ];

  // ---------------------------------------------------------------------------
  // Critical whitelist keywords — at least one must match for Critical to hold.
  // ---------------------------------------------------------------------------

  /// Keywords that provide strong deterministic evidence for Critical priority.
  static const _criticalEvidenceKeywords = [
    'fraud',
    'unauthorized',
    'suspicious',
    'security alert',
    'unusual sign',
    'account compromised',
    'emergency',
    'sos',
    'amber alert',
    'severe weather',
    'starts in',
    'starting now',
    'begins in',
    'boarding',
    'gate change',
    'gate changed',
    'flight',
    'payment failed',
    'transaction failed',
    'declined',
  ];

  // ---------------------------------------------------------------------------
  // High whitelist keywords — evidence needed for High priority to hold.
  // ---------------------------------------------------------------------------

  /// Keywords that provide evidence for High priority.
  static const _highEvidenceKeywords = [
    'meeting in',
    'standup',
    'interview',
    'arriving today',
    'out for delivery',
    'package',
    'appointment',
    'doctor',
    'prescription',
    'medicine',
  ];

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Evaluates the fused semantic analysis and extracted features,
  /// determining the final priority tier ('critical', 'high', 'medium', 'low').
  ///
  /// The method uses the ML-based look-again score as the starting point,
  /// then applies conservative deterministic overrides:
  /// 1. Compute raw priority from look-again score (tightened thresholds).
  /// 2. Apply category-based demotion for explicitly-low categories (promo, social).
  /// 3. Apply package-level and content-level ceiling overrides.
  /// 4. Apply Critical whitelist gate — Critical requires strong evidence.
  /// 5. Apply High whitelist gate — High requires specific evidence.
  ///
  /// The category-based priority is used to force demotion for known-low
  /// categories (promo, social), but does NOT compete with the score for
  /// categories like 'sys' or 'msg' that have neutral defaults. This ensures
  /// that a meeting reminder with score-based 'high' and category 'sys'
  /// (medium default) can still reach 'high' if it passes the High gate.
  static String resolvePriority({
    required AnalysisResult fusedResult,
    required ExtractedFeatures features,
    required AppNotification notification,
    double? lookAgainScore,
  }) {
    // Step 1: Start from the score-based priority (tightened thresholds)
    String priority = _fromLookAgainScore(lookAgainScore);

    // Step 2: Apply category-based adjustments.
    // Demotion: Categories with strong evidence of low importance (promo, social)
    // force the priority down.
    // Promotion: Categories with strong deterministic evidence (OTP, amount,
    // deadline) can promote the priority upward — the Critical/High gates in
    // steps 4-5 will still validate the final result.
    final categoryPriority = _fromCategory(
      fusedResult: fusedResult,
      features: features,
      notification: notification,
    );
    if (categoryPriority == 'low') {
      priority = 'low';
    } else if (categoryPriority == 'critical' && _isHigherThan('critical', priority)) {
      // Feature evidence (OTP, amount, deadline) warrants critical — promote.
      // The Critical gate in step 4 will validate this.
      priority = 'critical';
    } else if (categoryPriority == 'high' && _isHigherThan('high', priority)) {
      // Category evidence (finance, health, msg, email) warrants high — promote.
      // The High gate in step 5 will validate this.
      priority = 'high';
    }

    // Step 3: Apply deterministic ceiling overrides (package + content)
    priority = _applyPackageCeiling(notification, priority, _mediaPackages);
    priority = _applySocialCeiling(notification, priority);
    priority = _applyPackageCeiling(notification, priority, _entertainmentPackages);
    priority = _applyPackageCeiling(notification, priority, _promoPackages);
    priority = _applyContentCeiling(notification, priority, _mediaPlaybackKeywords, 'low');
    priority = _applyContentCeiling(notification, priority, _entertainmentRecoKeywords, 'low');
    priority = _applyContentCeiling(notification, priority, _promoContentKeywords, 'low');

    // Step 4: Critical whitelist gate
    priority = _applyCriticalGate(priority, features, notification);

    // Step 5: High whitelist gate
    priority = _applyHighGate(
      priority,
      features: features,
      notification: notification,
      fusedResult: fusedResult,
    );

    return priority;
  }

  // ---------------------------------------------------------------------------
  // Step 1: Score-based priority (tightened thresholds)
  // ---------------------------------------------------------------------------

  /// Converts a look-again score to a raw priority string.
  ///
  /// Thresholds are intentionally high to make Critical and High rare:
  /// - Critical: ≥ 0.90 (was 0.80)
  /// - High:     ≥ 0.70 (was 0.50)
  /// - Medium:   ≥ 0.25 (was 0.20)
  /// - Low:      < 0.25
  static String _fromLookAgainScore(double? score) {
    if (score == null) return 'medium';
    if (score >= 0.90) return 'critical';
    if (score >= 0.70) return 'high';
    if (score >= 0.25) return 'medium';
    return 'low';
  }

  // ---------------------------------------------------------------------------
  // Step 2: Category-based priority (preserves existing logic)
  // ---------------------------------------------------------------------------

  /// Determines priority from fused semantic category and extracted features.
  /// This is the original PolicyEngine logic, preserved for backward compat.
  static String _fromCategory({
    required AnalysisResult fusedResult,
    required ExtractedFeatures features,
    required AppNotification notification,
  }) {
    final category = fusedResult.category;

    // Critical tier
    if (category == 'finance' && features.amount != null) return 'critical';
    if (features.otp != null) return 'critical';
    if (category == 'scholarship' && features.hasDeadline) return 'critical';

    // High tier
    if (category == 'finance') return 'high';
    if (category == 'health') return 'high';
    if (category == 'msg' && !notification.isOngoing) return 'high';
    if (category == 'email' && !notification.isOngoing) return 'high';

    // Low tier
    if (category == 'promo') return 'low';
    if (category == 'social') return 'low';

    // Default
    return 'medium';
  }

  // ---------------------------------------------------------------------------
  // Step 3: Conservative merge
  // ---------------------------------------------------------------------------

  /// Returns the lower of two priorities (more conservative).
  static String _lowerOf(String a, String b) {
    final indexA = _priorityOrder.indexOf(a);
    final indexB = _priorityOrder.indexOf(b);
    // If either is unknown, treat as medium
    final safeA = indexA >= 0 ? indexA : 1;
    final safeB = indexB >= 0 ? indexB : 1;
    return _priorityOrder[safeA < safeB ? safeA : safeB];
  }

  // ---------------------------------------------------------------------------
  // Step 4: Package and content ceiling overrides
  // ---------------------------------------------------------------------------

  /// Caps priority to 'low' if the notification's package matches any fragment
  /// in the given list.
  static String _applyPackageCeiling(
    AppNotification notification,
    String currentPriority,
    List<String> packageFragments,
  ) {
    final pkg = notification.packageName.toLowerCase();
    final matchesPackage = packageFragments.any((frag) => pkg.contains(frag));
    if (matchesPackage && _isHigherThan(currentPriority, 'low')) {
      return 'low';
    }
    return currentPriority;
  }

  /// Social media ceiling: caps to 'low' for social engagement content.
  /// Preserves priority for direct messages and mentions (user-to-user interaction).
  static String _applySocialCeiling(
    AppNotification notification,
    String currentPriority,
  ) {
    final pkg = notification.packageName.toLowerCase();
    final isSocialPkg = _socialPackages.any((frag) => pkg.contains(frag));
    if (!isSocialPkg) return currentPriority;

    final text = '${notification.title} ${notification.content}'.toLowerCase();

    // Preserve DMs and mentions — these are direct user interactions
    final isDm = text.contains('sent you a message') ||
        text.contains('direct message') ||
        text.contains('dm from') ||
        text.contains('mentioned you') ||
        text.contains('replied to your');

    if (isDm) {
      // Cap at 'high' for social DMs — never Critical
      if (_isHigherThan(currentPriority, 'high')) return 'high';
      return currentPriority;
    }

    // Check for social engagement keywords
    final isSocialEngagement =
        _socialEngagementKeywords.any((kw) => text.contains(kw));

    if (isSocialEngagement && _isHigherThan(currentPriority, 'low')) {
      return 'low';
    }

    // For other social notifications from social packages, cap at medium
    if (_isHigherThan(currentPriority, 'medium')) {
      return 'medium';
    }

    return currentPriority;
  }

  /// Caps priority if the notification content matches any keyword in the given
  /// list. Used for media playback, entertainment reco, and promo content.
  static String _applyContentCeiling(
    AppNotification notification,
    String currentPriority,
    List<String> keywords,
    String ceiling,
  ) {
    final text = '${notification.title} ${notification.content}'.toLowerCase();
    final matchesKeyword = keywords.any((kw) => text.contains(kw));
    if (matchesKeyword && _isHigherThan(currentPriority, ceiling)) {
      return ceiling;
    }
    return currentPriority;
  }

  // ---------------------------------------------------------------------------
  // Step 5: Critical whitelist gate
  // ---------------------------------------------------------------------------

  /// Critical priority requires strong deterministic evidence.
  /// If the current priority is 'critical' but no whitelist signal is found,
  /// it is downgraded to 'high'.
  static String _applyCriticalGate(
    String currentPriority,
    ExtractedFeatures features,
    AppNotification notification,
  ) {
    if (currentPriority != 'critical') return currentPriority;

    // OTP is always valid evidence for Critical
    if (features.otp != null) return 'critical';

    // Finance with transaction amount is valid evidence
    if (features.amount != null) return 'critical';

    // Check for critical evidence keywords in text
    final text = '${notification.title} ${notification.content}'.toLowerCase();
    final hasCriticalEvidence =
        _criticalEvidenceKeywords.any((kw) => text.contains(kw));
    if (hasCriticalEvidence) return 'critical';

    // No strong evidence found — downgrade to high
    return 'high';
  }

  // ---------------------------------------------------------------------------
  // Step 6: High whitelist gate
  // ---------------------------------------------------------------------------

  /// High priority requires specific evidence of time-sensitivity or importance.
  /// If the current priority is 'high' but no whitelist signal is found,
  /// it is downgraded to 'medium'.
  static String _applyHighGate(
    String currentPriority, {
    required ExtractedFeatures features,
    required AppNotification notification,
    required AnalysisResult fusedResult,
  }) {
    if (currentPriority != 'high') return currentPriority;

    final category = fusedResult.category;

    // Finance category (non-promo) is valid for High
    if (category == 'finance') return 'high';

    // Health category is valid for High
    if (category == 'health') return 'high';

    // Direct messages (non-ongoing) are valid for High
    if (category == 'msg' && !notification.isOngoing) return 'high';

    // Direct emails (non-ongoing) are valid for High
    if (category == 'email' && !notification.isOngoing) return 'high';

    // Deadline with relevant category
    if (features.hasDeadline &&
        (category == 'scholarship' || category == 'finance' || category == 'email')) {
      return 'high';
    }

    // Check for high evidence keywords in text
    final text = '${notification.title} ${notification.content}'.toLowerCase();
    final hasHighEvidence =
        _highEvidenceKeywords.any((kw) => text.contains(kw));
    if (hasHighEvidence) return 'high';

    // No evidence found — downgrade to medium
    return 'medium';
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns true if [priority] is strictly higher than [threshold].
  static bool _isHigherThan(String priority, String threshold) {
    final priorityIdx = _priorityOrder.indexOf(priority);
    final thresholdIdx = _priorityOrder.indexOf(threshold);
    if (priorityIdx < 0 || thresholdIdx < 0) return false;
    return priorityIdx > thresholdIdx;
  }
}
