import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/storage/backup_exclusion_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupExclusionHelper Tests', () {
    const channel = MethodChannel('com.scope.attentions/storage');
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('backup_exclusion_test_');
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('excludeFromBackup returns false when file does not exist', () async {
      final nonExistentPath = '${tempDir.path}/non_existent.db';
      final result = await BackupExclusionHelper.excludeFromBackup(nonExistentPath);
      expect(result, isFalse);
    });

    test('excludeFromBackup calls MethodChannel and returns true on success', () async {
      final testFile = File('${tempDir.path}/attention_os.db');
      await testFile.writeAsString('dummy db content');

      String? invokedMethod;
      String? invokedPath;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        invokedMethod = methodCall.method;
        if (methodCall.arguments is Map) {
          invokedPath = methodCall.arguments['path'] as String?;
        }
        return true;
      });

      final result = await BackupExclusionHelper.excludeFromBackup(testFile.path);

      expect(result, isTrue);
      expect(invokedMethod, equals('excludeFromBackup'));
      expect(invokedPath, equals(testFile.path));
    });

    test('excludeFromBackup catches PlatformException gracefully', () async {
      final testFile = File('${tempDir.path}/rlhf_rules.json');
      await testFile.writeAsString('[]');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        throw PlatformException(code: 'UNSUPPORTED', message: 'Not supported on platform');
      });

      final result = await BackupExclusionHelper.excludeFromBackup(testFile.path);
      expect(result, isFalse);
    });

    test('excludeDatabaseAndRules executes without throwing exceptions', () async {
      expect(() async => await BackupExclusionHelper.excludeDatabaseAndRules(), returnsNormally);
    });
  });
}
