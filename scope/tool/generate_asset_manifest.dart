import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Build-time script to generate asset_manifest.json containing SHA-256 digests
/// and byte lengths for model and config assets.
void main() {
  final assetsDir = Directory('assets');
  if (!assetsDir.existsSync()) {
    stderr.writeln('Error: assets directory not found.');
    exit(1);
  }

  final targetAssets = [
    'assets/model.tflite',
    'assets/vocab.txt',
    'assets/rules.json',
  ];

  final manifestEntries = <String, Map<String, dynamic>>{};

  for (final relativePath in targetAssets) {
    final file = File(relativePath);
    if (!file.existsSync()) {
      stderr.writeln('Warning: Asset file not found at $relativePath');
      continue;
    }

    final bytes = file.readAsBytesSync();
    final digest = sha256.convert(bytes).toString();
    manifestEntries[relativePath] = {
      'sha256': digest,
      'length': bytes.length,
    };
    print('Manifest entry generated for $relativePath: sha256=$digest, length=${bytes.length}');
  }

  final manifestData = {
    'version': '1.0',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'assets': manifestEntries,
  };

  final manifestFile = File('assets/asset_manifest.json');
  manifestFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifestData),
  );

  print('Successfully generated ${manifestFile.path} with ${manifestEntries.length} entries.');
}
