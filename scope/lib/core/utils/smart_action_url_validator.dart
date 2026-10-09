import 'package:flutter/foundation.dart';
import 'package:scope/core/utils/smart_actions.dart';

/// Result of a URL validation check for Smart Actions.
class UrlValidationResult {
  final bool isValid;
  final bool wasBlocked;
  final String? sanitizedUrl;
  final String? scheme;
  final String? errorReason;

  const UrlValidationResult({
    required this.isValid,
    this.wasBlocked = false,
    this.sanitizedUrl,
    this.scheme,
    this.errorReason,
  });

  factory UrlValidationResult.valid(String url, String scheme) {
    return UrlValidationResult(
      isValid: true,
      wasBlocked: false,
      sanitizedUrl: url,
      scheme: scheme,
    );
  }

  factory UrlValidationResult.blocked(String scheme, String reason) {
    return UrlValidationResult(
      isValid: false,
      wasBlocked: true,
      scheme: scheme,
      errorReason: reason,
    );
  }

  factory UrlValidationResult.invalid(String reason) {
    return UrlValidationResult(
      isValid: false,
      wasBlocked: false,
      errorReason: reason,
    );
  }
}

/// Result of executing a Smart Action launch request.
class SmartActionLaunchResult {
  final bool success;
  final bool wasBlocked;
  final String? error;

  const SmartActionLaunchResult({
    required this.success,
    this.wasBlocked = false,
    this.error,
  });
}

/// Utility for validating and sanitizing Smart Action URLs before launching.
abstract final class SmartActionUrlValidator {
  /// Allowed URL schemes for web links, payment portals, and standard communication.
  static const Set<String> allowedSchemes = {
    'http',
    'https',
    'upi',
    'paytm',
    'phonepe',
    'gpay',
    'tez',
    'mailto',
    'tel',
  };

  /// Explicitly dangerous schemes that must be blocked to prevent intent redirection,
  /// local file access, or code execution exploits.
  static const Set<String> blockedSchemes = {
    'file',
    'javascript',
    'data',
    'content',
    'intent',
    'chrome',
    'about',
    'blob',
    'android-app',
  };

  /// Validates a raw URL string against security guardrails and scheme constraints.
  static UrlValidationResult validate(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return UrlValidationResult.invalid('URL string is empty');
    }

    String candidate = rawUrl.trim();

    // Check if URL is missing scheme but appears to be a domain/host
    final Uri? initialUri = Uri.tryParse(candidate);
    if (initialUri == null || !initialUri.hasScheme) {
      if (RegExp(r'^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(/.*)?$').hasMatch(candidate) ||
          candidate.startsWith('www.')) {
        candidate = 'https://$candidate';
      }
    }

    final Uri? uri = Uri.tryParse(candidate);
    if (uri == null) {
      return UrlValidationResult.invalid('Malformed URL format');
    }

    final String scheme = uri.scheme.toLowerCase();
    if (scheme.isEmpty) {
      return UrlValidationResult.invalid('Missing URL scheme');
    }

    // Guardrail 1: Check blocked schemes
    if (blockedSchemes.contains(scheme)) {
      return UrlValidationResult.blocked(
        scheme,
        'Dangerous URL scheme "$scheme" is blocked',
      );
    }

    // Guardrail 2: Check allowed schemes
    if (!allowedSchemes.contains(scheme)) {
      return UrlValidationResult.blocked(
        scheme,
        'Unsupported URL scheme "$scheme"',
      );
    }

    // Guardrail 3: Basic structural validation for web links
    if ((scheme == 'http' || scheme == 'https') && uri.host.isEmpty) {
      return UrlValidationResult.invalid('Invalid web URL missing host component');
    }

    return UrlValidationResult.valid(uri.toString(), scheme);
  }

  /// Redacts sensitive query parameters (tokens, passwords, codes, email, auth) from URL for logging.
  static String redactUrl(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      if (uri.queryParameters.isEmpty) return rawUrl;

      final Map<String, String> redactedParams = {};
      uri.queryParameters.forEach((key, value) {
        final lowerKey = key.toLowerCase();
        if (lowerKey.contains('token') ||
            lowerKey.contains('key') ||
            lowerKey.contains('auth') ||
            lowerKey.contains('pass') ||
            lowerKey.contains('code') ||
            lowerKey.contains('secret') ||
            lowerKey.contains('email') ||
            lowerKey.contains('phone')) {
          redactedParams[key] = '[REDACTED]';
        } else {
          redactedParams[key] = value;
        }
      });

      return uri.replace(queryParameters: redactedParams).toString();
    } catch (_) {
      return rawUrl.replaceAll(RegExp(r'=[^&]+'), '=[REDACTED]');
    }
  }

  /// Logs structured diagnostic reports for Smart Action launches while redacting PII.
  static void logDiagnostic({
    required SmartAction action,
    required String packageName,
    required UrlValidationResult result,
  }) {
    final String urlText = result.sanitizedUrl ?? action.url ?? 'none';
    final String redactedUrl = redactUrl(urlText);

    debugPrint('=== SMART ACTION INTENT LAUNCH REPORT ===');
    debugPrint('Action Type: ${action.type.name}');
    debugPrint('Package Name: $packageName');
    debugPrint('Target Scheme: ${result.scheme ?? "unknown"}');
    debugPrint('Target URL: $redactedUrl');
    debugPrint('Validation Status: ${result.isValid ? "PASSED" : "BLOCKED"}');
    if (!result.isValid) {
      debugPrint('Error Reason: ${result.errorReason}');
    }
    debugPrint('=========================================');
  }
}
