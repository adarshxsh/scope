import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/drift_notification_storage.dart';
import 'package:scope/core/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('SQLCipher Passphrase Management', () {
    test('getOrCreateDatabasePassphrase provisions and retrieves 256-bit key', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();

      final passphrase1 = await getOrCreateDatabasePassphrase(storage);
      expect(passphrase1.length, equals(64)); // 32 bytes = 64 hex characters = 256 bits

      final passphrase2 = await getOrCreateDatabasePassphrase(storage);
      expect(passphrase2, equals(passphrase1));
    });
  });

  group('SQLCipher Encryption & Operations at Rest', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('sqlcipher_test_env');
      dbPath = '${tempDir.path}/attention_os.db';
      FlutterSecureStorage.setMockInitialValues({});
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Reading encrypted database file with standard SQLite viewer fails with invalid database header error', () async {
      const storage = FlutterSecureStorage();
      final passphrase = await getOrCreateDatabasePassphrase(storage);

      // Create encrypted database directly with SQLCipher setup
      final db = sqlite3.open(dbPath);
      db.execute("PRAGMA key = '$passphrase';");
      db.execute("CREATE TABLE notifications_table (id TEXT PRIMARY KEY, title TEXT, content TEXT);");
      db.execute("INSERT INTO notifications_table (id, title, content) VALUES ('n1', 'Secret Title', 'Secret Payload');");
      db.close();

      // Attempt to read file without key using standard SQLite connection
      final unencryptedDb = sqlite3.open(dbPath);
      expect(() {
        unencryptedDb.select("SELECT * FROM notifications_table;");
      }, throwsA(isA<SqliteException>()));
      unencryptedDb.close();

      // Check raw file bytes on disk for plaintext exposure
      final rawBytes = File(dbPath).readAsBytesSync();
      final rawString = String.fromCharCodes(rawBytes);
      expect(rawString.contains('Secret Title'), isFalse);
      expect(rawString.contains('Secret Payload'), isFalse);
    });

    test('DriftNotificationStorage and ReviewQueueNotifier CRUD operations succeed on encrypted database', () async {
      const storage = FlutterSecureStorage();
      final passphrase = await getOrCreateDatabasePassphrase(storage);

      final db = AttentionDatabase.encrypted(secureStorage: storage, customPassphrase: passphrase, file: File(dbPath));
      final storageRepo = DriftNotificationStorage(db);

      final notification = AppNotification(
        id: 'notif_100',
        packageName: 'com.whatsapp',
        title: 'Confidential Message',
        content: 'Sensitive OTP 987654',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        state: ReviewState.ACTIVE,
      );

      await storageRepo.save(notification);

      final fetched = await storageRepo.getById('notif_100');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Confidential Message'));
      expect(fetched.content, equals('Sensitive OTP 987654'));

      final notifier = ReviewQueueNotifier(db);
      notifier.add(notification);
      expect(notifier.state.length, equals(1));
      expect(notifier.state.first.id, equals('notif_100'));

      notifier.reviewed('notif_100');
      expect(notifier.state.first.state, equals(ReviewState.REVIEWED));

      await db.close();
    });

    test('Migration automatically re-encrypts pre-existing unencrypted database file', () async {
      // 1. Create unencrypted SQLite database
      final plainDb = sqlite3.open(dbPath);
      plainDb.execute("CREATE TABLE notifications_table (id TEXT PRIMARY KEY, title TEXT, content TEXT);");
      plainDb.execute("INSERT INTO notifications_table (id, title, content) VALUES ('legacy_1', 'Legacy Title', 'Unencrypted Legacy Content');");
      plainDb.close();

      final rawBefore = String.fromCharCodes(File(dbPath).readAsBytesSync());
      expect(rawBefore.contains('Unencrypted Legacy Content'), isTrue);

      // 2. Perform migration logic
      const storage = FlutterSecureStorage();
      final passphrase = await getOrCreateDatabasePassphrase(storage);
      migrateUnencryptedToEncrypted(File(dbPath), passphrase);

      // 3. Verify plaintext is gone from raw file
      final rawAfter = String.fromCharCodes(File(dbPath).readAsBytesSync());
      expect(rawAfter.contains('Unencrypted Legacy Content'), isFalse);

      // 4. Verify data is readable using key
      final migratedDb = sqlite3.open(dbPath);
      migratedDb.execute("PRAGMA key = '$passphrase';");
      final rows = migratedDb.select("SELECT * FROM notifications_table;");
      expect(rows.length, equals(1));
      expect(rows.first['content'], equals('Unencrypted Legacy Content'));
      migratedDb.close();
    });
  });
}
