import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Utility class for scheme sanitization and safe URL execution using url_launcher.
abstract final class UrlLauncherUtils {
  /// Strictly whitelisted URI schemes for web link execution.
  static const Set<String> _allowedSchemes = {'http', 'https'};

  /// Sanitizes and validates a raw URL string.
  ///
  /// - Strips leading/trailing whitespace.
  /// - Prepends 'https://' if no scheme is present on a web domain.
  /// - Enforces that the URI scheme is strictly 'http' or 'https'.
  /// - Blocks local file schemes ('file:'), Android intents ('intent:'),
  ///   inline scripts ('javascript:'), content providers ('content:'), etc.
  /// - Returns the sanitized URL string if valid, otherwise returns null.
  static String? sanitizeUrl(String? rawUrl) {
    if (rawUrl == null) return null;
    var trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    Uri? uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    if (uri.scheme.isEmpty) {
      if (!trimmed.contains(':')) {
        trimmed = 'https://$trimmed';
        uri = Uri.tryParse(trimmed);
      }
    }

    if (uri == null) return null;

    final scheme = uri.scheme.toLowerCase();
    if (_allowedSchemes.contains(scheme)) {
      return uri.toString();
    }

    return null;
  }

  /// Returns true if the raw URL string evaluates to a safe HTTP/HTTPS scheme.
  static bool isSafeUrlScheme(String? rawUrl) {
    return sanitizeUrl(rawUrl) != null;
  }

  /// Attempts to launch a URL in an external application browser after validating its scheme.
  ///
  /// Enforces LaunchMode.externalApplication and local on-device scheme validation.
  static Future<UrlLaunchResult> launchUrlSafely(String? rawUrl) async {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return const UrlLaunchResult(
        success: false,
        isUnsafeScheme: false,
        errorMessage: 'No URL provided.',
      );
    }

    final sanitized = sanitizeUrl(rawUrl);
    if (sanitized == null) {
      return UrlLaunchResult(
        success: false,
        isUnsafeScheme: true,
        sanitizedUrl: null,
        errorMessage: 'Blocked unsafe or invalid URL scheme: $rawUrl',
      );
    }

    try {
      final uri = Uri.parse(sanitized);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return UrlLaunchResult(
          success: false,
          isUnsafeScheme: false,
          sanitizedUrl: sanitized,
          errorMessage: 'Could not launch URL: $sanitized',
        );
      }
      return UrlLaunchResult(
        success: true,
        isUnsafeScheme: false,
        sanitizedUrl: sanitized,
      );
    } catch (e) {
      debugPrint('UrlLauncherUtils launch failed: $e');
      return UrlLaunchResult(
        success: false,
        isUnsafeScheme: false,
        sanitizedUrl: sanitized,
        errorMessage: 'Failed to launch URL: $sanitized',
      );
    }
  }
}

/// Result object for url execution and scheme validation.
class UrlLaunchResult {
  final bool success;
  final bool isUnsafeScheme;
  final String? sanitizedUrl;
  final String? errorMessage;

  const UrlLaunchResult({
    required this.success,
    this.isUnsafeScheme = false,
    this.sanitizedUrl,
    this.errorMessage,
  });
}
