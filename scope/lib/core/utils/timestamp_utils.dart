import 'dart:math' as math;

/// Utility for normalizing and validating notification timestamps against clock skew,
/// seconds/milliseconds unit mismatches, and future timestamp anomalies.
class TimestampUtils {
  /// Maximum allowable future timestamp skew (1 day in milliseconds).
  static const int maxFutureSkewMs = 86400000;

  /// Threshold for 10-digit unix seconds timestamps (year 2286 in seconds = 10^10).
  static const int secondsThreshold = 10000000000;

  /// Threshold for 16-digit microseconds timestamps (year 2001 in microseconds = 10^14).
  static const int microsecondsThreshold = 100000000000000;

  /// Normalizes a timestamp integer to milliseconds since Unix epoch.
  /// Handles seconds vs. milliseconds vs. microseconds conversion, zero/negative timestamps,
  /// and future timestamp clamping.
  static int normalizeToMillis(int timestamp, {DateTime? now}) {
    final referenceNowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;

    if (timestamp <= 0) {
      return referenceNowMs;
    }

    int millis = timestamp;

    // Detect unit: seconds (10 digits) vs milliseconds (13 digits) vs microseconds (16 digits)
    if (timestamp < secondsThreshold) {
      millis = timestamp * 1000;
    } else if (timestamp > microsecondsThreshold) {
      millis = timestamp ~/ 1000;
    }

    // Clamp future timestamps exceeding reasonable clock skew to current time
    if (millis > referenceNowMs + maxFutureSkewMs) {
      return referenceNowMs;
    }

    return millis;
  }

  /// Calculates safe elapsed milliseconds from the notification timestamp to [now].
  /// Guaranteed to return a non-negative value (>= 0).
  static int getElapsedMs(int timestamp, {DateTime? now}) {
    final referenceNowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final normalizedTimestamp = normalizeToMillis(timestamp, now: now);
    return math.max(0, referenceNowMs - normalizedTimestamp);
  }

  /// Checks if a timestamp integer is valid (non-zero and non-negative).
  static bool isValidTimestamp(int timestamp) {
    return timestamp > 0;
  }
}
