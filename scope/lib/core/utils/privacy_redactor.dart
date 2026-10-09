/// Centralized Privacy Redactor service for masking sensitive PII fields
/// (OTPs, transaction amounts, email addresses, phone numbers, URLs).
class PrivacyRedactor {
  const PrivacyRedactor();

  static const PrivacyRedactor instance = PrivacyRedactor();

  /// Masks OTP codes (e.g. "123456" -> "12****", "987652" -> "98****").
  String? maskOtp(String? otp) {
    if (otp == null || otp.isEmpty) return otp;
    if (otp.length > 2) {
      return '${otp.substring(0, 2)}${'*' * (otp.length - 2)}';
    }
    return '*' * otp.length;
  }

  /// Masks transaction amounts (e.g. 500 / 500.0 / "Rs. 500" -> "****" or "Rs.****").
  String? maskAmount(dynamic amount) {
    if (amount == null) return null;
    final str = amount.toString().trim();
    if (str.isEmpty) return str;
    if (str.startsWith('Rs.') || str.startsWith('Rs. ')) {
      return 'Rs.****';
    }
    if (str.startsWith('\$')) {
      return '\$****';
    }
    return '****';
  }

  /// Masks email addresses (e.g. "user@example.com" -> "us****@example.com").
  String? maskEmail(String? email) {
    if (email == null || email.isEmpty) return email;
    if (email.contains('@')) {
      final parts = email.split('@');
      final local = parts[0];
      final domain = parts.sublist(1).join('@');
      final maskedLocal = local.length > 2
          ? '${local.substring(0, 2)}${'*' * (local.length - 2)}'
          : '*' * local.length;
      return '$maskedLocal@$domain';
    }
    return '*' * email.length;
  }

  /// Masks phone numbers (e.g. "+1234567890" -> "******7890").
  String? maskPhoneNumber(String? phone) {
    if (phone == null || phone.isEmpty) return phone;
    if (phone.length > 4) {
      return '${'*' * (phone.length - 4)}${phone.substring(phone.length - 4)}';
    }
    return '*' * phone.length;
  }

  /// Masks URLs / Hyperlinks (e.g. "https://example.com/reset" -> "https://example.com/****").
  String? maskUrl(String? url) {
    if (url == null || url.isEmpty) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.hasAuthority) {
        return '${uri.scheme}://${uri.authority}/****';
      }
    }
    return 'https://****';
  }

  /// Returns a new feature map with all sensitive PII fields masked.
  Map<String, dynamic> maskFeatures(Map<String, dynamic>? features) {
    if (features == null) return {};
    final result = Map<String, dynamic>.from(features);

    if (result.containsKey('otp')) {
      result['otp'] = maskOtp(result['otp']?.toString());
    }
    if (result.containsKey('amount')) {
      result['amount'] = maskAmount(result['amount']);
    }
    if (result.containsKey('urls') && result['urls'] is List) {
      result['urls'] = (result['urls'] as List).map((u) => maskUrl(u?.toString())).toList();
    }
    if (result.containsKey('emails') && result['emails'] is List) {
      result['emails'] = (result['emails'] as List).map((e) => maskEmail(e?.toString())).toList();
    }
    if (result.containsKey('phoneNumbers') && result['phoneNumbers'] is List) {
      result['phoneNumbers'] = (result['phoneNumbers'] as List).map((p) => maskPhoneNumber(p?.toString())).toList();
    }
    return result;
  }
}
