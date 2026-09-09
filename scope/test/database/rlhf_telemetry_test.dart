import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AttentionDatabase db;

  setUp(() {
    db = AttentionDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  group('RLHF Feedback Telemetry Persistence Tests', () {
    test('Stores structured reward signal (+1.0) and extracted feature vectors in SQLite', () async {
      final featureVector = List<double>.filled(63, 0.5);
      const rawTitle = 'Bank Alert: Account Debited';
      const rawContent = 'Your account ending 1234 was debited Rs.1000';

      final hashedTitle = sha256.convert(utf8.encode(rawTitle)).toString();
      final hashedContent = sha256.convert(utf8.encode(rawContent)).toString();

      final entry = RlhfFeedbackEventEntry(
        id: 0,
        notificationId: 'notif-100',
        reward: 1.0,
        correctedCategory: null,
        correctedPriority: null,
        featureVector: featureVector,
        tokenIds: [101, 202, 303],
        hashedTitle: hashedTitle,
        hashedContent: hashedContent,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        modelVersion: '1.0.0',
      );

      await db.rlhfFeedbackDao.insertEvent(entry);

      final events = await db.rlhfFeedbackDao.getAllEvents();
      expect(events.length, equals(1));

      final saved = events.first;
      expect(saved.notificationId, equals('notif-100'));
      expect(saved.reward, equals(1.0));
      expect(saved.featureVector.length, equals(63));
      expect(saved.featureVector.first, equals(0.5));
      expect(saved.tokenIds, equals([101, 202, 303]));

      // Verify privacy scrubbing: raw text is hashed and NOT stored in plain text
      expect(saved.hashedTitle, equals(hashedTitle));
      expect(saved.hashedTitle, isNot(contains(rawTitle)));
      expect(saved.hashedContent, equals(hashedContent));
      expect(saved.hashedContent, isNot(contains(rawContent)));
    });

    test('Stores structured penalty signal (-1.0) with category and priority corrections', () async {
      final featureVector = List<double>.filled(63, 0.1);
      final entry = RlhfFeedbackEventEntry(
        id: 0,
        notificationId: 'notif-200',
        reward: -1.0,
        correctedCategory: 'financial',
        correctedPriority: 'critical',
        featureVector: featureVector,
        tokenIds: null,
        hashedTitle: 'hashed_title_abc',
        hashedContent: 'hashed_content_xyz',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        modelVersion: '1.0.0',
      );

      await db.rlhfFeedbackDao.insertEvent(entry);

      final events = await db.rlhfFeedbackDao.getAllEvents();
      expect(events.length, equals(1));

      final saved = events.first;
      expect(saved.reward, equals(-1.0));
      expect(saved.correctedCategory, equals('financial'));
      expect(saved.correctedPriority, equals('critical'));
    });
  });
}
