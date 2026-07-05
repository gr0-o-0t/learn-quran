import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:learn_quran/core/services/engagement_service.dart';
import 'package:learn_quran/data/local/db/app_database.dart';
import 'package:learn_quran/data/local/db/knowledge_base_database.dart';
import 'package:learn_quran/data/repositories/quran_repository.dart';
import 'package:learn_quran/data/repositories/user_repository.dart';

String _formatDate(DateTime dt) {
  final year = dt.year;
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

void main() {
  late AppDatabase db;
  late KnowledgeBaseDatabase kbDb;
  late UserRepository userRepo;
  late QuranRepository quranRepo;
  late EngagementService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    kbDb = KnowledgeBaseDatabase.forTesting(NativeDatabase.memory());
    userRepo = UserRepository(db);
    quranRepo = QuranRepository(kbDb);
    service = EngagementService(userRepo, quranRepo);

    await kbDb.into(kbDb.verses).insert(VersesCompanion.insert(
          surahNumber: 1,
          ayahNumber: 1,
          juzNumber: 1,
          arabicText: 'arabic',
          englishText: 'Indeed, Allah is with those who have patience.',
          banglaText: 'bangla',
        ));
    await kbDb.into(kbDb.verses).insert(VersesCompanion.insert(
          surahNumber: 1,
          ayahNumber: 2,
          juzNumber: 1,
          arabicText: 'arabic',
          englishText: 'Honor your mother and father.',
          banglaText: 'bangla',
        ));
  });

  tearDown(() async {
    await db.close();
    await kbDb.close();
  });

  group('EngagementService.logReadingEvent', () {
    test('increments total ayahs, records last read, and detects topic', () async {
      await service.logReadingEvent(1, 1);

      expect(await userRepo.getEngagementValue('total_ayahs_read'), '1');
      expect(await userRepo.getEngagementValue('last_read_surah'), '1');
      expect(await userRepo.getEngagementValue('last_read_ayah'), '1');
      expect(await userRepo.getEngagementValue('last_read_topic'), 'patience');
      expect(await userRepo.getEngagementValue('last_read_timestamp'), isNotNull);
      expect(await userRepo.getEngagementValue('reading_streak'), '1');
      expect(await userRepo.getEngagementValue('last_read_date'), _formatDate(DateTime.now()));
    });

    test('accumulates total ayahs read across events without bumping streak same day', () async {
      await service.logReadingEvent(1, 1);
      await service.logReadingEvent(1, 2);

      expect(await userRepo.getEngagementValue('total_ayahs_read'), '2');
      expect(await userRepo.getEngagementValue('last_read_topic'), 'parents');
      expect(await userRepo.getEngagementValue('reading_streak'), '1');
    });

    test('extends streak on a consecutive day and resets after a gap', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await userRepo.setEngagementValue('last_read_date', _formatDate(yesterday));
      await userRepo.setEngagementValue('reading_streak', '3');

      await service.logReadingEvent(1, 1);
      expect(await userRepo.getEngagementValue('reading_streak'), '4');

      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
      await userRepo.setEngagementValue('last_read_date', _formatDate(threeDaysAgo));
      await userRepo.setEngagementValue('reading_streak', '4');

      await service.logReadingEvent(1, 1);
      expect(await userRepo.getEngagementValue('reading_streak'), '1');
    });
  });

  group('EngagementService.logSearchEvent', () {
    test('records query, detects sentiment, and tags unique topics', () async {
      await service.logSearchEvent('I feel very sad and anxious lately');

      expect(await userRepo.getEngagementValue('last_search_query'), 'I feel very sad and anxious lately');
      expect(await userRepo.getEngagementValue('recent_question_sentiment'), 'seeking_comfort');
      expect(await userRepo.getEngagementValue('search_tags'), '["general"]');
    });

    test('caps search tags at 5 unique topics, dropping the oldest', () async {
      final queries = [
        'how should I be patient with my parents',
        'why is forgiveness so important',
        'what is the mercy of Allah',
        'how do I pray salat correctly',
        'why give charity to the poor',
        'what is the ruling on fasting',
      ];
      for (final q in queries) {
        await service.logSearchEvent(q);
      }

      final tagsJson = await userRepo.getEngagementValue('search_tags');
      expect(tagsJson, isNotNull);
      final tags = List<String>.from(jsonDecode(tagsJson!));
      expect(tags.length, 5);
      // 'parents' was the first tag added and the oldest, so it's evicted once the 6th unique topic arrives.
      expect(tags, isNot(contains('parents')));
      expect(tags, contains('fasting'));
    });
  });

  group('EngagementService.compileSalatMetrics', () {
    test('sums completed prayers and computes streak from logs', () async {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      final twoDaysAgo = today.subtract(const Duration(days: 2));

      await userRepo.updateSalatLog(_formatDate(twoDaysAgo), 'fajr', true);
      await userRepo.updateSalatLog(_formatDate(yesterday), 'fajr', true);
      await userRepo.updateSalatLog(_formatDate(yesterday), 'dhuhr', true);
      await userRepo.updateSalatLog(_formatDate(today), 'fajr', true);

      await service.compileSalatMetrics();

      expect(await userRepo.getEngagementValue('total_prayers_completed'), '4');
      expect(await userRepo.getEngagementValue('prayer_streak'), '3');
      expect(await userRepo.getEngagementValue('last_logged_prayer_date'), _formatDate(today));
    });

    test('streak is 0 when no prayers were logged today or yesterday', () async {
      final longAgo = DateTime.now().subtract(const Duration(days: 10));
      await userRepo.updateSalatLog(_formatDate(longAgo), 'fajr', true);

      await service.compileSalatMetrics();

      expect(await userRepo.getEngagementValue('total_prayers_completed'), '1');
      expect(await userRepo.getEngagementValue('prayer_streak'), '0');
    });
  });
}
