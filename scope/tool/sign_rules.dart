import 'dart:convert';
import 'dart:io';
import 'package:scope/core/analysis/crypto_utils.dart';

void main(List<String> args) {
  final file = File('assets/rules.json');
  if (!file.existsSync()) {
    print('assets/rules.json not found!');
    exit(1);
  }

  final content = file.readAsStringSync();
  final decoded = json.decode(content);

  dynamic payload;
  if (decoded is Map<String, dynamic> && decoded.containsKey('payload')) {
    payload = decoded['payload'];
  } else {
    payload = decoded;
  }

  final payloadBytes = utf8.encode(json.encode(payload));
  final signatureBase64 = CryptoUtils.signEd25519(messageBytes: payloadBytes);

  final envelope = {
    'payload': payload,
    'signature': signatureBase64,
    'key_id': CryptoUtils.publisherKeyId,
  };

  const encoder = JsonEncoder.withIndent('  ');
  file.writeAsStringSync(encoder.convert(envelope));
  print('Successfully signed assets/rules.json envelope with key_id: ${CryptoUtils.publisherKeyId}');
}
