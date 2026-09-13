/// Architectural privacy guardrail utility for redacting sensitive content
/// (notification titles, content body, user PII) before logging or stringifying.
class Redactor {
  /// Redacts sensitive text, masking cleartext while preserving diagnostic length info.
  ///
  /// Examples:
  /// - `null` or `""` -> `"[EMPTY]"`
  /// - `"WhatsApp Verification"` -> `"[REDACTED len=21]"`
  static String redact(String? text) {
    if (text == null || text.trim().isEmpty) {
      return '[EMPTY]';
    }
    return '[REDACTED len=${text.length}]';
  }

  /// Returns a redacted map representation for notification logging / diagnostics.
  static Map<String, dynamic> redactNotificationMap(Map<String, dynamic> map) {
    final copy = Map<String, dynamic>.from(map);
    if (copy.containsKey('title')) {
      copy['title'] = redact(copy['title']?.toString());
    }
    if (copy.containsKey('content')) {
      copy['content'] = redact(copy['content']?.toString());
    }
    if (copy.containsKey('body')) {
      copy['body'] = redact(copy['body']?.toString());
    }
    return copy;
  }
}
