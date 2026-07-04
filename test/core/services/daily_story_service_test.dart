import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:learn_quran/core/services/daily_story_service.dart';
import 'package:learn_quran/core/services/llm_service.dart';
import 'package:learn_quran/data/local/db/app_database.dart';
import 'package:learn_quran/data/repositories/user_repository.dart';

String _formatDate(DateTime dt) {
  final year = dt.year;
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

class CountingLlmService extends LlmService {
  int callCount = 0;
  String response = 'Title: Test Reflection\n\nThis is a test story body.';

  @override
  Stream<String> generateResponseStream(String prompt, String ragContext) async* {
    callCount++;
    yield response;
  }
}

void main() {
  late AppDatabase db;
  late UserRepository userRepo;
  late CountingLlmService llm;
  late DailyStoryService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    userRepo = UserRepository(db);
    llm = CountingLlmService();
    service = DailyStoryService(userRepo, llm);
  });

  tearDown(() async {
    await db.close();
  });

  group('DailyStoryService caching', () {
    test('compiles and caches a story on first call', () async {
      final story = await service.getOrCompileDailyStory();

      expect(story, llm.response);
      expect(llm.callCount, 1);
      expect(await userRepo.getEngagementValue('daily_story'), llm.response);
      expect(await userRepo.getEngagementValue('daily_story_date'), _formatDate(DateTime.now()));
    });

    test('returns the cached story on a later call the same day without recompiling', () async {
      await service.getOrCompileDailyStory();
      expect(llm.callCount, 1);

      final second = await service.getOrCompileDailyStory();

      expect(second, llm.response);
      expect(llm.callCount, 1);
    });

    test('recompiles once the cached story is from a previous day', () async {
      await service.getOrCompileDailyStory();
      expect(llm.callCount, 1);

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await userRepo.setEngagementValue('daily_story_date', _formatDate(yesterday));
      llm.response = 'Title: New Day\n\nA fresh reflection.';

      final story = await service.getOrCompileDailyStory();

      expect(story, 'Title: New Day\n\nA fresh reflection.');
      expect(llm.callCount, 2);
      expect(await userRepo.getEngagementValue('daily_story_date'), _formatDate(DateTime.now()));
    });
  });

  group('DailyStoryService.compileNewDailyStory', () {
    test('builds a prompt from engagement metrics and returns the LLM output verbatim', () async {
      await userRepo.setEngagementValue('total_ayahs_read', '42');
      await userRepo.setEngagementValue('reading_streak', '7');
      await userRepo.setEngagementValue('last_read_surah', '2');
      await userRepo.setEngagementValue('last_read_ayah', '153');
      await userRepo.setEngagementValue('last_read_topic', 'patience');

      final story = await service.compileNewDailyStory();

      expect(story, llm.response);
      expect(llm.callCount, 1);
      // Does not touch the cache — only getOrCompileDailyStory does.
      expect(await userRepo.getEngagementValue('daily_story'), isNull);
    });

    test('falls back to defaults when no engagement history exists', () async {
      final story = await service.compileNewDailyStory();

      expect(story, llm.response);
      expect(llm.callCount, 1);
    });
  });

  group('DailyStoryService with the real LlmService (mock inference fallback)', () {
    test('produces a non-empty, title-prefixed reflection end to end', () async {
      final realService = DailyStoryService(userRepo, LlmService());

      final story = await realService.getOrCompileDailyStory();

      expect(story, isNotEmpty);
      expect(story, startsWith('Title:'));
      expect(await userRepo.getEngagementValue('daily_story'), story);
    });
  });
}
