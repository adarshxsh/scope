import 'package:flutter/foundation.dart';

/// Centralized PrivacyLogger helper that redacts sensitive entity patterns
/// (OTPs, financial amounts, emails, phone numbers, account/order/transaction IDs)
/// from log outputs while preserving non-sensitive diagnostic context and execution metadata.
class PrivacyLogger {
  PrivacyLogger._();

  // Reused entity extraction patterns
  static final RegExp _emailRegex = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
  );

  static final RegExp _phoneRegex = RegExp(
    r'\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{4}\b|\b1800[-.\s]?[A-Z0-9]{3,4}[-.\s]?[A-Z0-9]{4}\b',
    caseSensitive: false,
  );

  static final RegExp _amountRegex = RegExp(
    r'(?:₹|rs\.?|inr|usd|\$|eur|€|gbp|£|aed)\s*([0-9]+(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)|([0-9]+(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?)\s*(?:rs\.?|inr|usd|eur|gbp|aed)',
    caseSensitive: false,
  );

  static final RegExp _accountAndIdRegex = RegExp(
    r'\b(?:acc|account|a/c|txn|txnid|transaction|utr|upi|order|ord|ref|reference|tracking|awb|shipment|coupon|promo code|voucher)[\s#:.-]*[A-Z0-9-]{4,}\b',
    caseSensitive: false,
  );

  static final RegExp _otpDigitsRegex = RegExp(r'\b\d{4,8}\b');

  // Metadata patterns to preserve (e.g. inference time, timestamps, IDs in metadata key-values)
  static final RegExp _metadataPrefixRegex = RegExp(
    r'(?:inference\s*time|time|timestamp|score|priority|notification_id|id)\s*[:=]\s*$',
    caseSensitive: false,
  );

  /// Synchronously sanitizes input text by masking sensitive entities with standard category tokens.
  static String sanitize(String input) {
    if (input.isEmpty) return input;

    String text = input;

    // 1. Redact Emails
    text = text.replaceAll(_emailRegex, '[EMAIL]');

    // 2. Redact Phone Numbers
    text = text.replaceAll(_phoneRegex, '[PHONE]');

    // 3. Redact Financial Amounts
    text = text.replaceAll(_amountRegex, '[AMOUNT]');

    // 4. Redact Account / Order / Transaction / Ref / Tracking IDs
    text = text.replaceAll(_accountAndIdRegex, '[ACCOUNT]');

    // 5. Redact OTPs (4-8 digit numeric codes, avoiding years & execution metadata)
    text = text.replaceAllMapped(_otpDigitsRegex, (match) {
      final value = match.group(0)!;
      final number = int.tryParse(value);

      // Preserve year numbers (2020 - 2030)
      if (number != null && number >= 2020 && number <= 2030) {
        return value;
      }

      // Check context before match to avoid redacting execution metadata
      final prefix = text.substring(0, match.start);
      if (_metadataPrefixRegex.hasMatch(prefix.trimRight())) {
        return value;
      }

      // Check if preceded by "us" or time/microsecond context or inside brackets
      if (prefix.trimRight().endsWith('Inference Time:') ||
          prefix.trimRight().endsWith('us') ||
          prefix.trimRight().endsWith('MS:')) {
        return value;
      }

      return '[OTP]';
    });

    return text;
  }

  /// Logs a sanitized debug message via debugPrint.
  static void log(String message) {
    final sanitized = sanitize(message);
    debugPrint(sanitized);
  }

  /// Alias for log.
  static void debug(String message) {
    log(message);
  }

  /// Helper for structured notification logging.
  static void logNotification(
    String action, {
    required String packageName,
    required String title,
    String? content,
    String? extra,
  }) {
    final buffer = StringBuffer('$action: $packageName - ${sanitize(title)}');
    if (content != null && content.isNotEmpty) {
      buffer.write(' | Body: ${sanitize(content)}');
    }
    if (extra != null && extra.isNotEmpty) {
      buffer.write(' | $extra');
    }
    log(buffer.toString());
  }
}
