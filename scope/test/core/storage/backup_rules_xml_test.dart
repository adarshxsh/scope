import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android Backup XML Rules Tests', () {
    test('AndroidManifest.xml contains dataExtractionRules and fullBackupContent attributes', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue, reason: 'AndroidManifest.xml must exist');

      final content = manifestFile.readAsStringSync();
      expect(content, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
      expect(content, contains('android:fullBackupContent="@xml/backup_rules"'));
    });

    test('data_extraction_rules.xml includes attention_os.db and rlhf_rules.json under cloud-backup and device-transfer', () {
      final xmlFile = File('android/app/src/main/res/xml/data_extraction_rules.xml');
      expect(xmlFile.existsSync(), isTrue, reason: 'data_extraction_rules.xml must exist');

      final content = xmlFile.readAsStringSync();
      expect(content, contains('<cloud-backup>'));
      expect(content, contains('</cloud-backup>'));
      expect(content, contains('<device-transfer>'));
      expect(content, contains('</device-transfer>'));

      final cloudSection = content.substring(content.indexOf('<cloud-backup>'), content.indexOf('</cloud-backup>'));
      final transferSection = content.substring(content.indexOf('<device-transfer>'), content.indexOf('</device-transfer>'));

      expect(cloudSection, contains('path="attention_os.db"'));
      expect(cloudSection, contains('path="rlhf_rules.json"'));

      expect(transferSection, contains('path="attention_os.db"'));
      expect(transferSection, contains('path="rlhf_rules.json"'));
    });

    test('backup_rules.xml includes attention_os.db and rlhf_rules.json', () {
      final xmlFile = File('android/app/src/main/res/xml/backup_rules.xml');
      expect(xmlFile.existsSync(), isTrue, reason: 'backup_rules.xml must exist');

      final content = xmlFile.readAsStringSync();
      expect(content, contains('<full-backup-content>'));
      expect(content, contains('path="attention_os.db"'));
      expect(content, contains('path="rlhf_rules.json"'));
    });
  });
}
