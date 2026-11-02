import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/keystore_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.scope.keystore');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  group('KeyStoreBridge Unit Tests', () {
    test('getOrCreateDatabasePassphrase returns passphrase from native MethodChannel', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          if (call.method == 'getOrCreateDatabasePassphrase') {
            return 'a1b2c3d4e5f67890123456789abcdef0123456789abcdef0123456789abcdef0';
          }
          return null;
        },
      );

      final passphrase = await KeyStoreBridge.getOrCreateDatabasePassphrase();
      expect(passphrase, equals('a1b2c3d4e5f67890123456789abcdef0123456789abcdef0123456789abcdef0'));
    });

    test('getOrCreateDatabasePassphrase handles PlatformException gracefully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          throw PlatformException(
            code: 'KEYSTORE_ERROR',
            message: 'Hardware key store failure',
          );
        },
      );

      final passphrase = await KeyStoreBridge.getOrCreateDatabasePassphrase();
      expect(passphrase, isNull);
    });

    test('getOrCreateDatabasePassphrase handles general exceptions gracefully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          throw Exception('Unexpected error');
        },
      );

      final passphrase = await KeyStoreBridge.getOrCreateDatabasePassphrase();
      expect(passphrase, isNull);
    });
  });
}
