import 'dart:convert';
import 'package:pinenacl/ed25519.dart';

void main() {
  final sk = SigningKey.generate();
  final vk = sk.verifyKey;
  print("Private seed base64: ${base64.encode(sk)}");
  print("Public key base64: ${base64.encode(vk)}");
}
