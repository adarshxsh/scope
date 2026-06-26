import 'package:scope/core/analysis/extracted_features.dart';

/// Extract features from notification content and title using regular expressions.
class FeatureExtractor {
  /// Normalize raw text for clean feature extraction.
  static String normalize(String text) {
    return text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Extracts structured features from combined [title] and [content].
  static ExtractedFeatures extract({required String title, required String content}) {
    final combined = normalize('$title $content');

    return ExtractedFeatures(
      otp: _extractOtp(combined),
      amount: _extractAmount(combined),
      hasDeadline: _extractDeadline(combined),
      urls: _extractUrls(combined),
      emails: _extractEmails(combined),
      phoneNumbers: _extractPhoneNumbers(combined),
    );
  }

  static String? _extractOtp(String text) {
    // Pattern to look for a numeric code of 4 to 8 digits.
    final digitRegex = RegExp(r'\b\d{4,8}\b');

    // Context check: Must have terms like otp, code, pin, password etc.
    final contextRegex = RegExp(
      r'(?:otp|verification|code|pin|verify|one-time|password)',
      caseSensitive: false,
    );
    if (!contextRegex.hasMatch(text)) return null;

    final matches = digitRegex.allMatches(text);
    for (final match in matches) {
      final value = match.group(0);
      if (value != null) {
        // Filter out typical years (e.g. 2020 to 2030)
        final numVal = int.tryParse(value);
        if (numVal != null && numVal >= 2020 && numVal <= 2030) {
          continue;
        }
        return value;
      }
    }
    return null;
  }

  static double? _extractAmount(String text) {
    // Pattern matches currency symbol/name followed by digit grouping
    final amountRegex = RegExp(
      r'(?:Rs\.?|INR|USD|\$)\s*([0-9,]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );

    final match = amountRegex.firstMatch(text);
    if (match != null) {
      final cleanedStr = match.group(1)?.replaceAll(',', '');
      if (cleanedStr != null) {
        return double.tryParse(cleanedStr);
      }
    }
    return null;
  }

  static bool _extractDeadline(String text) {
    // Relative dates, deadline keywords, countdown timers
    final deadlineRegex = RegExp(
      r'\b(?:deadline|closes? in|ends? in|hours? left|days? left|expires?|due|urgent|action required|today|tomorrow|tonight)\b',
      caseSensitive: false,
    );
    return deadlineRegex.hasMatch(text);
  }

  static List<String> _extractUrls(String text) {
    final urlRegex = RegExp(
      r'https?:\/\/[^\s]+',
      caseSensitive: false,
    );
    return urlRegex.allMatches(text).map((m) => m.group(0)!).toList();
  }

  static List<String> _extractEmails(String text) {
    final emailRegex = RegExp(
      r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
    );
    return emailRegex.allMatches(text).map((m) => m.group(0)!).toList();
  }

  static List<String> _extractPhoneNumbers(String text) {
    // Match common phone formats, toll free lines like 1800-XXX-XXXX, and mobile layouts
    final phoneRegex = RegExp(
      r'\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{4}\b|\b1800[-.\s]?[A-Z0-9]{3,4}[-.\s]?[A-Z0-9]{4}\b',
      caseSensitive: false,
    );
    return phoneRegex.allMatches(text).map((m) => m.group(0)!).toList();
  }
}
