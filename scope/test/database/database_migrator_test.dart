import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/database/database_migrator.dart';

void main() {
  group('DatabaseMigrator Unit Tests', () {
    late Directory tempDir;
    late File dbFile;
    const testKey = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('migrator_test_');
      dbFile = File('${tempDir.path}/attention_os.db');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('isPlaintextDatabase detects unencrypted SQLite headers correctly', () {
      expect(DatabaseMigrator.isPlaintextDatabase(dbFile), isFalse);

      // Create plaintext SQLite database
      final db = sqlite3.open(dbFile.path);
      db.execute('CREATE TABLE dummy (id INTEGER PRIMARY KEY);');
      db.close();

      expect(DatabaseMigrator.isPlaintextDatabase(dbFile), isTrue);
    });

    test('migratePlaintextToEncrypted executes non-destructive, atomic migration', () async {
      // 1. Setup legacy plaintext database with mock tables and rows
      final srcDb = sqlite3.open(dbFile.path);
      srcDb.execute('''
        CREATE TABLE notifications_table (
          id TEXT PRIMARY KEY,
          package_name TEXT,
          title TEXT,
          content TEXT,
          timestamp INTEGER
        );
      ''');
      srcDb.execute('''
        INSERT INTO notifications_table VALUES
        ('n1', 'com.whatsapp', 'Alice', 'Hello world', 1000),
        ('n2', 'com.slack', 'Bob', 'Project update', 2000);
      ''');

      srcDb.execute('''
        CREATE TABLE review_queue_table (
          id INTEGER PRIMARY KEY,
          notification_id TEXT,
          priority TEXT
        );
      ''');
      srcDb.execute("INSERT INTO review_queue_table VALUES (1, 'n1', 'high');");
      srcDb.close();

      expect(DatabaseMigrator.isPlaintextDatabase(dbFile), isTrue);

      // 2. Perform migration
      await DatabaseMigrator.migratePlaintextToEncrypted(dbFile, testKey);

      // 3. Verify file is no longer recognized as plaintext
      expect(DatabaseMigrator.isPlaintextDatabase(dbFile), isFalse);

      // 4. Verify contents can be read when supplying encryption key
      DatabaseMigrator.prepareForOpening(dbFile, testKey);
      final encryptedDb = sqlite3.open(dbFile.path);
      encryptedDb.execute("PRAGMA key = '$testKey';");

      final notifications = encryptedDb.select('SELECT * FROM notifications_table');
      expect(notifications.length, equals(2));
      expect(notifications.first['title'], equals('Alice'));
      expect(notifications.last['title'], equals('Bob'));

      final reviewQueue = encryptedDb.select('SELECT * FROM review_queue_table');
      expect(reviewQueue.length, equals(1));
      expect(reviewQueue.first['priority'], equals('high'));

      encryptedDb.close();
    });
  });
}
