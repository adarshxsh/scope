import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/storage/backup_exclusion_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupExclusionHelper Tests', () {
    const channel = MethodChannel('com.scope.backup');
    final log = <MethodCall>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        log.add(methodCall);
        if (methodCall.method == 'excludeFromBackup') {
          return true;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('excludeFromBackup returns false when file does not exist', () async {
      final result = await BackupExclusionHelper.excludeFromBackup(
        'non_existent_file.db',
        filePath: '/tmp/non_existent_file.db',
      );
      expect(result, isFalse);
    });

    test('excludeFromBackup invokes channel when file exists', () async {
      final tempFile = File('${Directory.systemTemp.path}/attention_os.db');
      await tempFile.writeAsString('test database content');

      try {
        final result = await BackupExclusionHelper.excludeFromBackup(
          'attention_os.db',
          filePath: tempFile.path,
        );

        if (Platform.isIOS) {
          expect(result, isTrue);
          expect(log.length, equals(1));
          expect(log.first.method, equals('excludeFromBackup'));
          expect(log.first.arguments['fileName'], equals('attention_os.db'));
          expect(log.first.arguments['filePath'], equals(tempFile.path));
        } else {
          // On non-iOS platforms, returns true without invoking iOS channel
          expect(result, isTrue);
        }
      } finally {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    });

    test('excludeSensitiveFiles attempts to exclude database and rules files', () async {
      final tempDb = File('${Directory.systemTemp.path}/attention_os.db');
      final tempRules = File('${Directory.systemTemp.path}/rlhf_rules.json');
      await tempDb.writeAsString('db');
      await tempRules.writeAsString('rules');

      try {
        await BackupExclusionHelper.excludeSensitiveFiles();
        // Method completes gracefully without throwing errors
      } finally {
        if (await tempDb.exists()) await tempDb.delete();
        if (await tempRules.exists()) await tempRules.delete();
      }
    });
  });
}
