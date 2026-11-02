import 'dart:math';

/// Configuration for Differential Privacy parameters.
class DifferentialPrivacyConfig {
  /// Maximum L2 norm allowed for gradient/weight updates.
  final double clipNorm;

  /// Noise scale multiplier relative to clipNorm (sigma).
  final double noiseMultiplier;

  /// Target privacy epsilon (privacy budget parameter).
  final double targetEpsilon;

  /// Target privacy delta (privacy budget parameter).
  final double targetDelta;

  /// Maximum allowed cumulative epsilon before FL updates are halted.
  final double maxPrivacyBudgetEpsilon;

  const DifferentialPrivacyConfig({
    this.clipNorm = 1.0,
    this.noiseMultiplier = 0.1,
    this.targetEpsilon = 2.0,
    this.targetDelta = 1e-5,
    this.maxPrivacyBudgetEpsilon = 10.0,
  });

  Map<String, dynamic> toJson() => {
        'clipNorm': clipNorm,
        'noiseMultiplier': noiseMultiplier,
        'targetEpsilon': targetEpsilon,
        'targetDelta': targetDelta,
        'maxPrivacyBudgetEpsilon': maxPrivacyBudgetEpsilon,
      };
}

/// Core Differential Privacy operations, L2 norm clipping, noise addition, and PII redaction.
class DifferentialPrivacy {
  final DifferentialPrivacyConfig config;
  final Random _random;

  DifferentialPrivacy({
    DifferentialPrivacyConfig? config,
    Random? random,
  })  : config = config ?? const DifferentialPrivacyConfig(),
        _random = random ?? Random();

  /// Calculates the L2 norm (Euclidean norm) of a vector.
  double calculateL2Norm(List<double> vector) {
    if (vector.isEmpty) return 0.0;
    double sumOfSquares = 0.0;
    for (final val in vector) {
      if (val.isNaN || val.isInfinite) {
        throw ArgumentError('Vector contains non-finite numerical value (NaN or Infinity)');
      }
      sumOfSquares += val * val;
    }
    return sqrt(sumOfSquares);
  }

  /// Clips vector to maximum L2 norm `clipNorm`.
  /// Formula: v_clipped = v * min(1.0, clipNorm / ||v||_2)
  List<double> clipVector(List<double> vector, double clipNorm) {
    if (clipNorm <= 0) {
      throw ArgumentError('clipNorm must be strictly positive');
    }
    final norm = calculateL2Norm(vector);
    if (norm == 0.0 || norm <= clipNorm) {
      return List<double>.from(vector);
    }
    final scale = clipNorm / norm;
    return vector.map((v) => v * scale).toList();
  }

  /// Generates a standard normal random variable N(0, 1) using the Box-Muller transform.
  double _nextGaussian() {
    double u1 = _random.nextDouble();
    while (u1 <= 1e-15) {
      u1 = _random.nextDouble(); // Prevent log(0)
    }
    final u2 = _random.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }

  /// Adds Gaussian noise N(0, (noiseScale)^2) to each component of vector.
  List<double> addGaussianNoise(List<double> vector, double noiseScale) {
    if (noiseScale < 0) {
      throw ArgumentError('noiseScale cannot be negative');
    }
    if (noiseScale == 0.0) {
      return List<double>.from(vector);
    }
    return vector.map((v) => v + (_nextGaussian() * noiseScale)).toList();
  }

  /// Combined operation: clips vector to L2 norm and applies calibrated Gaussian noise.
  List<double> clipAndNoise(List<double> vector) {
    final clipped = clipVector(vector, config.clipNorm);
    final noiseScale = config.noiseMultiplier * config.clipNorm;
    return addGaussianNoise(clipped, noiseScale);
  }

  /// Sanitizes text by redacting PII (emails, phone numbers, OTPs, currency/amounts, passwords, tokens).
  static String sanitizePII(String text) {
    if (text.isEmpty) return text;

    String sanitized = text;

    // 1. Email addresses
    final emailRegex = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', caseSensitive: false);
    sanitized = sanitized.replaceAll(emailRegex, '[REDACTED_EMAIL]');

    // 2. Bearer tokens or Auth headers
    final tokenRegex = RegExp(r'\b(bearer|token|key|secret|auth)[=\s:]+[A-Za-z0-9_-]{8,}\b', caseSensitive: false);
    sanitized = sanitized.replaceAll(tokenRegex, '[REDACTED_CREDENTIAL]');

    // 3. OTP codes / Verification codes (e.g. 4 to 8 digit numbers in context)
    final otpRegex = RegExp(r'\b(code|otp|verification|pin|password|token)\b[^\d\n\r]{0,20}\d{4,8}\b', caseSensitive: false);
    sanitized = sanitized.replaceAll(otpRegex, '[REDACTED_OTP]');

    // 4. Financial amounts / Currencies (e.g., $100, Rs.500, USD 50, €20, ₹1000)
    final amountRegex = RegExp(r'(\$|₹|Rs\.?|USD|EUR|GBP|€|£)\s*\d+(?:[\.,]\d+)?', caseSensitive: false);
    sanitized = sanitized.replaceAll(amountRegex, '[REDACTED_AMOUNT]');

    // 5. Phone numbers (10+ digits, international format)
    final phoneRegex = RegExp(r'(\+\d{1,4}[\s.-]?)?\(?\d{2,4}\)?[\s.-]?\d{3,4}[\s.-]?\d{3,4}\b');
    sanitized = sanitized.replaceAllMapped(phoneRegex, (m) {
      final matchStr = m.group(0)!;
      final digitsOnly = matchStr.replaceAll(RegExp(r'\D'), '');
      if (digitsOnly.length >= 7) {
        return '[REDACTED_PHONE]';
      }
      return matchStr;
    });

    // 6. Standalone OTP numbers (4-8 consecutive digits)
    final digitsRegex = RegExp(r'\b\d{4,8}\b');
    sanitized = sanitized.replaceAllMapped(digitsRegex, (m) {
      // Avoid redacting years like 2026 or 2025 unless explicitly matching OTP patterns
      final str = m.group(0)!;
      final num = int.tryParse(str);
      if (num != null && (num >= 1900 && num <= 2099)) {
        return str;
      }
      return '[REDACTED_NUMERIC]';
    });

    return sanitized;
  }

  /// Calculates approximate cumulative epsilon spent over `rounds` local FL rounds using standard DP composition.
  /// eps_total ≈ rounds * sqrt(2 * log(1.25 / delta)) / noiseMultiplier (for noiseMultiplier > 0).
  double calculateEpsilonSpent(int rounds) {
    if (rounds <= 0) return 0.0;
    if (config.noiseMultiplier <= 0) return double.infinity;

    final delta = config.targetDelta > 0 ? config.targetDelta : 1e-5;
    final perRoundEps = sqrt(2.0 * log(1.25 / delta)) / config.noiseMultiplier;
    // Advanced composition bound approximation: eps_total = perRoundEps * sqrt(2 * rounds * log(1 / delta))
    return perRoundEps * sqrt(2.0 * rounds * log(1.0 / delta));
  }
}
