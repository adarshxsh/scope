import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

void main() {
  final assetsDir = Directory('assets');
  if (!assetsDir.existsSync()) {
    stderr.writeln('Error: assets directory not found at ${assetsDir.absolute.path}');
    exit(1);
  }

  final manifest = <String, String>{};
  final files = assetsDir.listSync().whereType<File>();

  for (final file in files) {
    final fileName = path.basename(file.path);
    if (fileName == 'asset_manifest.json') continue;

    final bytes = file.readAsBytesSync();
    final digest = sha256.convert(bytes).toString();
    final assetPath = 'assets/$fileName';
    manifest[assetPath] = digest;
    print('Manifest entry: $assetPath -> $digest');
  }

  final manifestFile = File('assets/asset_manifest.json');
  const encoder = JsonEncoder.withIndent('  ');
  manifestFile.writeAsStringSync('${encoder.convert(manifest)}\n');
  print('Successfully generated ${manifestFile.path} with ${manifest.length} entries.');
}
