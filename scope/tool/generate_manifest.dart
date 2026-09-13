// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

/// Seed for deterministic release keypair.
/// Seed: 32 bytes hex: 0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20
const String releaseKeySeedHex =
    '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20';

/// Converts hex string to byte list.
List<int> hexToBytes(String hex) {
  final bytes = <int>[];
  for (int i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return bytes;
}

/// Converts byte list to hex string.
String bytesToHex(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
}

/// Helper to compute canonical manifest payload bytes for signing.
List<int> getCanonicalManifestPayloadBytes(Map<String, dynamic> manifestMap) {
  final filesMap = manifestMap['files'] as Map<String, dynamic>? ?? {};
  final sortedFileKeys = filesMap.keys.toList()..sort();
  final Map<String, String> sortedFiles = {};
  for (final key in sortedFileKeys) {
    sortedFiles[key] = filesMap[key].toString();
  }

  final canonicalMap = <String, dynamic>{
    'files': sortedFiles,
    'version': manifestMap['version'] ?? '1.0.0',
  };

  final canonicalJsonStr = jsonEncode(canonicalMap);
  return utf8.encode(canonicalJsonStr);
}

Future<void> main(List<String> args) async {
  final ed25519 = Ed25519();
  final seedBytes = hexToBytes(releaseKeySeedHex);
  final keyPair = await ed25519.newKeyPairFromSeed(seedBytes);
  final publicKey = await keyPair.extractPublicKey();
  final publicKeyHex = bytesToHex(publicKey.bytes);

  print('=== Manifest Generator & Signer ===');
  print('Public Key (Hex): $publicKeyHex');

  final assetPaths = [
    'assets/model.tflite',
    'assets/rules.json',
    'assets/vocab.txt',
  ];

  final Map<String, String> filesHashes = {};

  for (final path in assetPaths) {
    final file = File(path);
    if (!file.existsSync()) {
      print('Warning: File not found: $path');
      continue;
    }
    final bytes = await file.readAsBytes();
    final hash = sha256.convert(bytes).toString();
    filesHashes[path] = hash;
    print('Hashed $path: $hash');
  }

  final manifestMap = <String, dynamic>{
    'version': '1.0.0',
    'files': filesHashes,
  };

  final payloadBytes = getCanonicalManifestPayloadBytes(manifestMap);
  final signature = await ed25519.sign(payloadBytes, keyPair: keyPair);
  final signatureHex = bytesToHex(signature.bytes);

  manifestMap['signature'] = signatureHex;

  final encoder = JsonEncoder.withIndent('  ');
  final manifestJsonStr = encoder.convert(manifestMap);

  final manifestFile = File('assets/manifest.json');
  await manifestFile.writeAsString(manifestJsonStr);
  print('Successfully wrote signed assets/manifest.json!');
  print('Signature (Hex): $signatureHex');
}
