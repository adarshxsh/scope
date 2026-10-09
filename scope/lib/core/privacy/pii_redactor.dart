import 'package:flutter/foundation.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/pii_audit_logger.dart';

/// Result of a PII redaction operation.
class RedactionResult {
  final String redactedText;
  final List<PiiType> detectedPiiTypes;
  final bool fallbackApplied;

  const RedactionResult({
    required this.redactedText,
    required this.detectedPiiTypes,
    this.fallbackApplied = false,
  });
}

/// On-device PII Detection and Redaction Engine for AttentionOS.
///
/// Refactors system components to eliminate plaintext PII storage and unredacted UI rendering.
/// Fully executes on-device without external network dependencies and with low memory overhead.
class PiiRedactor {
  // Regex patterns for PII detection
  static final RegExp _emailRegex = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
    caseSensitive: false,
  );

  static final RegExp _phoneRegex = RegExp(
    r'\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b',
  );

  static final RegExp _creditCardRegex = RegExp(
    r'\b(?:\d[ -]*?){13,19}\b',
  );

  static final RegExp _credentialRegex = RegExp(
    r'\b(?:password|passcode|secret|pin|auth_token)\s*[:=]\s*\S+',
    caseSensitive: false,
  );

  static final RegExp _accountRegex = RegExp(
    r'\b(?:A/C|account|acct|card|ssn|pan|aadhaar)\b(?:\s*(?:no|num|number|ending in|#)?[:\s]*)?([A-Za-z0-9]{4,16})',
    caseSensitive: false,
  );

  static final RegExp _otpContextRegex = RegExp(
    r'\b(?:code|verification|verify|otp|pin|passcode|auth|sign-in|login)\b',
    caseSensitive: false,
  );

  static final RegExp _digitCodeRegex = RegExp(
    r'\b\d{4,8}\b',
  );

  /// Redacts PII from raw text and returns a [RedactionResult].
  static RedactionResult redactText(
    String input, {
    String? explicitOtp,
    List<String>? explicitPhones,
    List<String>? explicitEmails,
  }) {
    if (input.isEmpty) {
      return const RedactionResult(redactedText: '', detectedPiiTypes: []);
    }

    final detected = <PiiType>{};
    String result = input;

    try {
      // 1. Redact Explicit OTP if provided
      if (explicitOtp != null && explicitOtp.trim().isNotEmpty && explicitOtp.length >= 4) {
        final otpVal = explicitOtp.trim();
        if (result.contains(otpVal)) {
          result = result.replaceAll(otpVal, '[REDACTED CODE]');
          detected.add(PiiType.otp);
        }
      }

      // 2. Redact OTPs in context or matching standalone 4-8 digit codes in OTP messages
      if (_otpContextRegex.hasMatch(result)) {
        final matches = _digitCodeRegex.allMatches(result).toList();
        for (final match in matches) {
          final code = match.group(0)!;
          // Avoid redacting 4-digit years like 2026 or 2025 unless explicitly part of OTP
          if (code.length == 4 && (code.startsWith('202') || code.startsWith('201'))) {
            continue;
          }
          result = result.replaceAll(code, '[REDACTED CODE]');
          detected.add(PiiType.otp);
        }
      }

      // 3. Redact Credit / Debit Card Numbers
      if (_creditCardRegex.hasMatch(result)) {
        result = result.replaceAllMapped(_creditCardRegex, (m) {
          final raw = m.group(0)!.replaceAll(RegExp(r'[\s-]'), '');
          if (raw.length >= 13 && raw.length <= 19) {
            final last4 = raw.substring(raw.length - 4);
            return '•••• •••• •••• $last4';
          }
          return m.group(0)!;
        });
        detected.add(PiiType.card);
      }

      // 4. Redact Passwords and Cleartext Credentials
      if (_credentialRegex.hasMatch(result)) {
        result = result.replaceAllMapped(_credentialRegex, (m) {
          final matched = m.group(0)!;
          final parts = matched.split(RegExp(r'[:=]'));
          if (parts.length >= 2) {
            return '${parts[0]}: [REDACTED CREDENTIAL]';
          }
          return '[REDACTED CREDENTIAL]';
        });
        detected.add(PiiType.credential);
      }

      // 5. Redact Bank Account / Reference Numbers
      if (_accountRegex.hasMatch(result)) {
        result = result.replaceAllMapped(_accountRegex, (m) {
          final full = m.group(0)!;
          final accNum = m.group(1);
          if (accNum != null && accNum.length >= 4) {
            final prefix = full.substring(0, full.indexOf(accNum));
            final masked = accNum.length > 4
                ? '••••${accNum.substring(accNum.length - 4)}'
                : '••••';
            return '$prefix$masked';
          }
          return full;
        });
        detected.add(PiiType.accountNumber);
      }

      // 6. Redact Email Addresses
      if (_emailRegex.hasMatch(result)) {
        result = result.replaceAllMapped(_emailRegex, (_) => '[REDACTED EMAIL]');
        detected.add(PiiType.email);
      }
      if (explicitEmails != null) {
        for (final email in explicitEmails) {
          if (email.isNotEmpty && result.contains(email)) {
            result = result.replaceAll(email, '[REDACTED EMAIL]');
            detected.add(PiiType.email);
          }
        }
      }

      // 7. Redact Phone Numbers
      if (_phoneRegex.hasMatch(result)) {
        result = result.replaceAllMapped(_phoneRegex, (_) => '[REDACTED PHONE]');
        detected.add(PiiType.phone);
      }
      if (explicitPhones != null) {
        for (final phone in explicitPhones) {
          if (phone.length >= 7 && result.contains(phone)) {
            result = result.replaceAll(phone, '[REDACTED PHONE]');
            detected.add(PiiType.phone);
          }
        }
      }

      return RedactionResult(
        redactedText: result,
        detectedPiiTypes: detected.toList(),
      );
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[PII Redactor Error] $e\n$stack');
      }
      // Fallback error recovery path
      return _applySafeFallbackRedaction(input, e.toString());
    }
  }

  /// Transforms an [AppNotification] to ensure no cleartext PII or credentials are exposed.
  static AppNotification redactNotification(
    AppNotification notification, {
    String source = 'SYSTEM',
  }) {
    try {
      final features = notification.extractedFeatures;
      final explicitOtp = features?['otp'] as String?;
      final explicitPhones = (features?['phoneNumbers'] as List?)?.cast<String>();
      final explicitEmails = (features?['emails'] as List?)?.cast<String>();

      final titleRedaction = redactText(
        notification.title,
        explicitOtp: explicitOtp,
        explicitPhones: explicitPhones,
        explicitEmails: explicitEmails,
      );

      final contentRedaction = redactText(
        notification.content,
        explicitOtp: explicitOtp,
        explicitPhones: explicitPhones,
        explicitEmails: explicitEmails,
      );

      final explanationRedaction = notification.explanation != null
          ? redactText(
              notification.explanation!,
              explicitOtp: explicitOtp,
              explicitPhones: explicitPhones,
              explicitEmails: explicitEmails,
            )
          : null;

      final allDetected = <PiiType>{
        ...titleRedaction.detectedPiiTypes,
        ...contentRedaction.detectedPiiTypes,
        if (explanationRedaction != null) ...explanationRedaction.detectedPiiTypes,
      };

      // Redact structured features
      Map<String, dynamic>? redactedFeatures;
      if (features != null) {
        redactedFeatures = Map<String, dynamic>.from(features);
        if (redactedFeatures.containsKey('otp') && redactedFeatures['otp'] != null) {
          redactedFeatures['otp'] = '[REDACTED CODE]';
          allDetected.add(PiiType.otp);
        }
        if (redactedFeatures.containsKey('phoneNumbers') && redactedFeatures['phoneNumbers'] is List) {
          final phones = (redactedFeatures['phoneNumbers'] as List).cast<String>();
          redactedFeatures['phoneNumbers'] = phones.map((_) => '[REDACTED PHONE]').toList();
          if (phones.isNotEmpty) allDetected.add(PiiType.phone);
        }
        if (redactedFeatures.containsKey('emails') && redactedFeatures['emails'] is List) {
          final emails = (redactedFeatures['emails'] as List).cast<String>();
          redactedFeatures['emails'] = emails.map((_) => '[REDACTED EMAIL]').toList();
          if (emails.isNotEmpty) allDetected.add(PiiType.email);
        }
      }

      // Log audit event if PII was detected and redacted
      if (allDetected.isNotEmpty) {
        PiiAuditLogger.logRedaction(
          notificationId: notification.id,
          piiTypes: allDetected.toList(),
          action: 'REDACT_$source',
          success: true,
        );
      }

      return notification.copyWith(
        title: titleRedaction.redactedText,
        content: contentRedaction.redactedText,
        explanation: explanationRedaction?.redactedText,
        extractedFeatures: redactedFeatures,
      );
    } catch (e) {
      PiiAuditLogger.logFallback(
        notificationId: notification.id,
        action: 'REDACT_NOTIFICATION_$source',
        errorMessage: e.toString(),
      );

      return notification.copyWith(
        title: '[REDACTED TITLE]',
        content: '[REDACTED CONTENT]',
        explanation: 'Summary unavailable due to privacy redaction fallback.',
        extractedFeatures: notification.extractedFeatures != null
            ? {
                ...notification.extractedFeatures!,
                'otp': '[REDACTED CODE]',
              }
            : null,
      );
    }
  }

  /// Safe fallback error recovery function if standard regex processing fails.
  static RedactionResult _applySafeFallbackRedaction(String input, String errorMessage) {
    // Replace numbers and sensitive markers safely
    final fallbackText = input
        .replaceAll(RegExp(r'\b\d{4,19}\b'), '[REDACTED NUMERIC]')
        .replaceAll(RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'), '[REDACTED EMAIL]');

    return RedactionResult(
      redactedText: fallbackText,
      detectedPiiTypes: PiiType.values,
      fallbackApplied: true,
    );
  }
}
