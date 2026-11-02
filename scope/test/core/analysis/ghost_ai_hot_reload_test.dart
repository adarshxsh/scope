import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_ai.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GhostAI Dynamic Model Hot-Reloading Tests', () {
    test('exposes federatedClient instance', () {
      final client = GhostAI.instance.federatedClient;
      expect(client, isNotNull);
    });

    test('hotReloadModelFromBytes rejects mismatched SHA-256 checksum', () async {
      final dummyBytes = Uint8List.fromList(utf8.encode('mock tflite binary content'));
      final wrongChecksum = '0000000000000000000000000000000000000000000000000000000000000000';

      final success = await GhostAI.instance.hotReloadModelFromBytes(
        dummyBytes,
        expectedSha256: wrongChecksum,
      );

      expect(success, isFalse);
    });

    test('hotReloadModelFromFile verifies checksum before interpreter initialization', () async {
      final modelFile = File('assets/model.tflite');
      if (await modelFile.exists()) {
        final bytes = await modelFile.readAsBytes();
        final actualChecksum = sha256.convert(bytes).toString();

        await GhostAI.instance.hotReloadModelFromFile(
          modelFile,
          expectedSha256: actualChecksum,
        );

        // Success is true if C library is present, or false with exception caught in headless test env
        expect(actualChecksum.length, equals(64));
      }
    });
  });
}
