import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android Backup and Data Extraction Rules Tests', () {
    final manifestFile = File('android/app/src/main/AndroidManifest.xml');
    final dataExtractionRulesFile =
        File('android/app/src/main/res/xml/data_extraction_rules.xml');
    final backupRulesFile =
        File('android/app/src/main/res/xml/backup_rules.xml');

    test('AndroidManifest.xml contains backup restriction attributes', () {
      expect(manifestFile.existsSync(), isTrue,
          reason: 'AndroidManifest.xml should exist');
      final manifestContent = manifestFile.readAsStringSync();

      expect(manifestContent, contains('android:allowBackup="false"'),
          reason: 'AndroidManifest.xml must explicitly set android:allowBackup="false"');
      expect(manifestContent,
          contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
          reason:
              'AndroidManifest.xml must specify android:dataExtractionRules="@xml/data_extraction_rules"');
      expect(manifestContent, contains('android:fullBackupContent="@xml/backup_rules"'),
          reason:
              'AndroidManifest.xml must specify android:fullBackupContent="@xml/backup_rules"');
    });

    test(
        'res/xml/data_extraction_rules.xml excludes database, sharedpref, file, root, and external domains',
        () {
      expect(dataExtractionRulesFile.existsSync(), isTrue,
          reason: 'res/xml/data_extraction_rules.xml should exist');
      final content = dataExtractionRulesFile.readAsStringSync();

      expect(content, contains('<data-extraction-rules>'));
      expect(content, contains('</data-extraction-rules>'));
      expect(content, contains('<cloud-backup>'));
      expect(content, contains('</cloud-backup>'));
      expect(content, contains('<device-to-device-backup>'));
      expect(content, contains('</device-to-device-backup>'));

      // Check explicit database file exclusions
      for (final dbFile in [
        'attention_os.db',
        'attention_os.db-journal',
        'attention_os.db-shm',
        'attention_os.db-wal'
      ]) {
        expect(content, contains('path="$dbFile"'),
            reason: 'Data extraction rules must exclude $dbFile');
      }

      // Check domain exclusions
      for (final domain in [
        'database',
        'sharedpref',
        'file',
        'root',
        'external'
      ]) {
        expect(content, contains('domain="$domain"'),
            reason:
                'Data extraction rules must exclude domain $domain');
      }
    });

    test(
        'res/xml/backup_rules.xml excludes database, sharedpref, file, root, and external domains',
        () {
      expect(backupRulesFile.existsSync(), isTrue,
          reason: 'res/xml/backup_rules.xml should exist');
      final content = backupRulesFile.readAsStringSync();

      expect(content, contains('<full-backup-content>'));
      expect(content, contains('</full-backup-content>'));

      // Check explicit database file exclusions
      for (final dbFile in [
        'attention_os.db',
        'attention_os.db-journal',
        'attention_os.db-shm',
        'attention_os.db-wal'
      ]) {
        expect(content, contains('path="$dbFile"'),
            reason: 'Backup rules must exclude $dbFile');
      }

      // Check domain exclusions
      for (final domain in [
        'database',
        'sharedpref',
        'file',
        'root',
        'external'
      ]) {
        expect(content, contains('domain="$domain"'),
            reason: 'Backup rules must exclude domain $domain');
      }
    });
  });
}
