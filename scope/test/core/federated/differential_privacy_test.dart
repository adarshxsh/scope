import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/federated/differential_privacy.dart';

void main() {
  group('DifferentialPrivacy Unit Tests', () {
    late DifferentialPrivacy dp;

    setUp(() {
      dp = DifferentialPrivacy(
        config: const DifferentialPrivacyConfig(
          clipNorm: 1.0,
          noiseMultiplier: 0.1,
          targetEpsilon: 2.0,
          targetDelta: 1e-5,
          maxPrivacyBudgetEpsilon: 10.0,
        ),
      );
    });

    test('calculateL2Norm calculates correct Euclidean norm', () {
      expect(dp.calculateL2Norm([0.0, 0.0, 0.0]), equals(0.0));
      expect(dp.calculateL2Norm([3.0, 4.0]), equals(5.0));
      expect(dp.calculateL2Norm([1.0, 1.0, 1.0, 1.0]), equals(2.0));
    });

    test('calculateL2Norm throws ArgumentError on NaN or Infinity', () {
      expect(() => dp.calculateL2Norm([1.0, double.nan]), throwsArgumentError);
      expect(() => dp.calculateL2Norm([double.infinity, 2.0]), throwsArgumentError);
    });

    test('clipVector clips vectors exceeding max norm threshold', () {
      final vec = [3.0, 4.0]; // Norm is 5.0
      final clipped = dp.clipVector(vec, 1.0); // Clip to max norm 1.0

      expect(dp.calculateL2Norm(clipped), closeTo(1.0, 1e-6));
      expect(clipped[0], closeTo(3.0 / 5.0, 1e-6));
      expect(clipped[1], closeTo(4.0 / 5.0, 1e-6));
    });

    test('clipVector leaves vectors within norm bound unmodified', () {
      final vec = [0.2, 0.3]; // Norm ~ 0.36 < 1.0
      final clipped = dp.clipVector(vec, 1.0);

      expect(clipped, equals(vec));
    });

    test('clipVector throws ArgumentError for non-positive clipNorm', () {
      expect(() => dp.clipVector([1.0, 1.0], 0.0), throwsArgumentError);
      expect(() => dp.clipVector([1.0, 1.0], -1.0), throwsArgumentError);
    });

    test('addGaussianNoise adds noise with scale > 0 and leaves vector untouched if scale == 0', () {
      final vec = [1.0, 2.0, 3.0];
      final exact = dp.addGaussianNoise(vec, 0.0);
      expect(exact, equals(vec));

      final noisy = dp.addGaussianNoise(vec, 0.5);
      expect(noisy.length, equals(vec.length));
      expect(noisy, isNot(equals(vec)));
    });

    test('addGaussianNoise throws ArgumentError on negative noiseScale', () {
      expect(() => dp.addGaussianNoise([1.0], -0.1), throwsArgumentError);
    });

    test('sanitizePII redacts email addresses, phone numbers, OTPs, amounts, and credentials', () {
      final rawText =
          r'User john.doe@example.com called +1 555-123-4567. OTP code is 987654. Debited $150.00 or Rs.500 from account. Auth token key=abc12345678.';

      final sanitized = DifferentialPrivacy.sanitizePII(rawText);

      expect(sanitized, contains('[REDACTED_EMAIL]'));
      expect(sanitized, isNot(contains('john.doe@example.com')));
      expect(sanitized, contains('[REDACTED_PHONE]'));
      expect(sanitized, contains('[REDACTED_OTP]'));
      expect(sanitized, isNot(contains('987654')));
      expect(sanitized, contains('[REDACTED_AMOUNT]'));
      expect(sanitized, isNot(contains(r'$150.00')));
      expect(sanitized, contains('[REDACTED_CREDENTIAL]'));
    });

    test('calculateEpsilonSpent calculates correct cumulative epsilon growth', () {
      final eps0 = dp.calculateEpsilonSpent(0);
      final eps1 = dp.calculateEpsilonSpent(1);
      final eps5 = dp.calculateEpsilonSpent(5);

      expect(eps0, equals(0.0));
      expect(eps1, greaterThan(0.0));
      expect(eps5, greaterThan(eps1));
    });
  });
}
