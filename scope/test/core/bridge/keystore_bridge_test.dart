import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:scope/core/bridge/keystore_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KeyStoreBridge bridge;
  late MethodChannel channel;
  late List<MethodCall> log;

  setUp(() {
    channel = const MethodChannel('com.scope.keystore.test');
    bridge = KeyStoreBridge(channel: channel);
    log = [];
  });

  void mockHandler(Future<dynamic> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return handler(call);
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('KeyStoreBridge', () {
    group('getDatabasePassphrase', () {
      test('returns passphrase from channel when available', () async {
        const expectedPassphrase = 'aabbccdd11223344556677889900aabbccdd11223344556677889900aabbccdd';
        mockHandler((call) async {
          if (call.method == 'getDatabasePassphrase') {
            return expectedPassphrase;
          }
          return null;
        });

        final passphrase = await bridge.getDatabasePassphrase();
        expect(passphrase, expectedPassphrase);
        expect(log.single.method, 'getDatabasePassphrase');
      });

      test('returns fallback passphrase on PlatformException', () async {
        mockHandler((call) async {
          throw PlatformException(code: 'KEYSTORE_ERROR', message: 'Failed to access Keystore');
        });

        final passphrase = await bridge.getDatabasePassphrase();
        expect(passphrase, isNotEmpty);
        expect(passphrase.length, 64);
      });

      test('returns fallback passphrase on MissingPluginException', () async {
        final unmockedBridge = KeyStoreBridge(
          channel: const MethodChannel('com.scope.unregistered'),
        );
        final passphrase = await unmockedBridge.getDatabasePassphrase();
        expect(passphrase, isNotEmpty);
      });
    });

    group('isStrongBoxSupported', () {
      test('returns true when StrongBox is supported', () async {
        mockHandler((call) async => true);

        final result = await bridge.isStrongBoxSupported();
        expect(result, isTrue);
        expect(log.single.method, 'isStrongBoxSupported');
      });

      test('returns false on PlatformException', () async {
        mockHandler((call) async {
          throw PlatformException(code: 'ERROR');
        });

        final result = await bridge.isStrongBoxSupported();
        expect(result, isFalse);
      });
    });

    group('isHardwareBacked', () {
      test('returns true when key is hardware-backed', () async {
        mockHandler((call) async => true);

        final result = await bridge.isHardwareBacked();
        expect(result, isTrue);
        expect(log.single.method, 'isHardwareBacked');
      });

      test('returns false on PlatformException', () async {
        mockHandler((call) async {
          throw PlatformException(code: 'ERROR');
        });

        final result = await bridge.isHardwareBacked();
        expect(result, isFalse);
      });
    });
  });
}
