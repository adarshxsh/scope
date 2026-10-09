import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android Backup Configuration Tests', () {
    final manifestFile = File('android/app/src/main/AndroidManifest.xml');
    final extractionRulesFile =
        File('android/app/src/main/res/xml/data_extraction_rules.xml');

    test('AndroidManifest.xml exists and explicitly disables backups', () {
      expect(manifestFile.existsSync(), isTrue,
          reason: 'AndroidManifest.xml must exist');
      final content = manifestFile.readAsStringSync();

      expect(content.contains('android:allowBackup="false"'), isTrue,
          reason:
              'AndroidManifest.xml must contain android:allowBackup="false"');
      expect(content.contains('android:fullBackupContent="false"'), isTrue,
          reason:
              'AndroidManifest.xml must contain android:fullBackupContent="false"');
      expect(
          content.contains(
              'android:dataExtractionRules="@xml/data_extraction_rules"'),
          isTrue,
          reason:
              'AndroidManifest.xml must reference @xml/data_extraction_rules');
    });

    test(
        'data_extraction_rules.xml exists and blocks cloud-backup and device-transfer',
        () {
      expect(extractionRulesFile.existsSync(), isTrue,
          reason: 'data_extraction_rules.xml must exist');
      final content = extractionRulesFile.readAsStringSync();

      expect(content.contains('<data-extraction-rules>'), isTrue);
      expect(content.contains('<cloud-backup>'), isTrue);
      expect(content.contains('<device-transfer>'), isTrue);

      for (final domain in [
        'root',
        'file',
        'database',
        'sharedpref',
        'external'
      ]) {
        expect(content.contains('<exclude domain="$domain"'), isTrue,
            reason: 'data_extraction_rules.xml must exclude domain $domain');
      }
    });
  });
}
