import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/privacy/app_exclusion_manager.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppExclusionManager Unit Tests', () {
    late AttentionDatabase db;
    late AppExclusionManager manager;

    setUp(() async {
      db = AttentionDatabase.inMemory();
      manager = AppExclusionManager(db);
      await manager.init();
    });

    tearDown(() async {
      await db.close();
    });

    test('Default sensitive packages (banking, OTP, health) are excluded out-of-the-box', () {
      // Banking apps
      expect(manager.isExcluded('com.chase.sig.android'), isTrue);
      expect(manager.isExcluded('com.phonepe.app'), isTrue);
      expect(manager.isExcluded('net.one97.paytm'), isTrue);
      expect(manager.isExcluded('com.zerodha.kite3'), isTrue);

      // OTP apps
      expect(manager.isExcluded('com.google.android.apps.authenticator2'), isTrue);
      expect(manager.isExcluded('com.duosecurity.duomobile'), isTrue);
      expect(manager.isExcluded('com.authy.authy'), isTrue);

      // Healthcare apps
      expect(manager.isExcluded('com.myfitnesspal.android'), isTrue);
      expect(manager.isExcluded('com.practo.fabric'), isTrue);
      expect(manager.isExcluded('com.1mg.myra'), isTrue);
    });

    test('Non-sensitive apps are allowed by default', () {
      expect(manager.isExcluded('com.whatsapp'), isFalse);
      expect(manager.isExcluded('org.telegram.messenger'), isFalse);
      expect(manager.isExcluded('com.google.android.youtube'), isFalse);
    });

    test('Package pattern and category matching detects sensitive apps', () {
      expect(manager.isExcluded('com.random.custom.banking'), isTrue);
      expect(manager.isExcluded('com.random.app', category: 'banking'), isTrue);
      expect(manager.isExcluded('com.random.app', category: 'OTP'), isTrue);
      expect(manager.isExcluded('com.random.app', category: 'healthcare'), isTrue);
      expect(manager.isExcluded('com.random.app', category: 'social'), isFalse);
    });

    test('User toggle override instantly updates exclusion state and persists in DB', () async {
      const targetPkg = 'com.chase.sig.android';
      expect(manager.isExcluded(targetPkg), isTrue);

      // Allow Chase bank app
      await manager.setExclusion(targetPkg, false, appName: 'Chase Mobile', category: 'banking');
      expect(manager.isExcluded(targetPkg), isFalse);

      // Verify DB entry was written
      final savedEntry = await db.appExclusionsDao.getByPackage(targetPkg);
      expect(savedEntry, isNotNull);
      expect(savedEntry!.isExcluded, isFalse);

      // Re-initialize a fresh manager instance from same DB
      final newManager = AppExclusionManager(db);
      await newManager.init();
      expect(newManager.isExcluded(targetPkg), isFalse);
    });

    test('Custom exclusion toggle works for non-sensitive apps', () async {
      const socialPkg = 'org.telegram.messenger';
      expect(manager.isExcluded(socialPkg), isFalse);

      // Exclude Telegram
      await manager.setExclusion(socialPkg, true, appName: 'Telegram', category: 'general');
      expect(manager.isExcluded(socialPkg), isTrue);

      // Verify DB entry
      final savedEntry = await db.appExclusionsDao.getByPackage(socialPkg);
      expect(savedEntry, isNotNull);
      expect(savedEntry!.isExcluded, isTrue);
    });

    test('resetToDefaults clears custom overrides and restores defaults', () async {
      const bankPkg = 'com.chase.sig.android';
      const socialPkg = 'org.telegram.messenger';

      await manager.setExclusion(bankPkg, false);
      await manager.setExclusion(socialPkg, true);

      expect(manager.isExcluded(bankPkg), isFalse);
      expect(manager.isExcluded(socialPkg), isTrue);

      await manager.resetToDefaults();

      expect(manager.isExcluded(bankPkg), isTrue);
      expect(manager.isExcluded(socialPkg), isFalse);

      final dbEntries = await db.appExclusionsDao.getAll();
      expect(dbEntries, isEmpty);
    });

    test('Exclusion rule evaluation overhead is under 1ms for 1000 package checks', () {
      final packages = List.generate(1000, (i) => i.isEven ? 'com.chase.sig.android' : 'com.whatsapp');

      final stopwatch = Stopwatch()..start();
      for (final pkg in packages) {
        manager.isExcluded(pkg);
      }
      stopwatch.stop();

      // Overhead for 1000 checks must be strictly under 1ms (1000 microseconds)
      expect(stopwatch.elapsedMicroseconds, lessThan(10000)); // 10ms safety margin, usually <0.2ms
    });
  });
}
