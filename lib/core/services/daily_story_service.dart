import '../../data/repositories/user_repository.dart';
import 'llm_service.dart';

class DailyStoryService {
  final UserRepository _userRepo;
  final LlmService _llmService;

  DailyStoryService(this._userRepo, this._llmService);

  /// Retrieves the compiled daily story from local cache or compiles a new one if not present/outdated.
  Future<String> getOrCompileDailyStory() async {
    final todayStr = _formatDate(DateTime.now());
    final cachedDate = await _userRepo.getEngagementValue('daily_story_date');
    final cachedStory = await _userRepo.getEngagementValue('daily_story');

    if (cachedDate == todayStr && cachedStory != null) {
      return cachedStory;
    }

    // Compile new story
    final story = await compileNewDailyStory();
    await _userRepo.setEngagementValue('daily_story', story);
    await _userRepo.setEngagementValue('daily_story_date', todayStr);
    return story;
  }

  /// Direct compilation of a new story using the current user engagement state and local LLM.
  Future<String> compileNewDailyStory() async {
    final totalAyahs = await _userRepo.getEngagementValue('total_ayahs_read') ?? '0';
    final lastReadSurah = await _userRepo.getEngagementValue('last_read_surah') ?? '1';
    final lastReadAyah = await _userRepo.getEngagementValue('last_read_ayah') ?? '1';
    final lastReadTopic = await _userRepo.getEngagementValue('last_read_topic') ?? 'general';
    final readingStreak = await _userRepo.getEngagementValue('reading_streak') ?? '0';
    final searchTags = await _userRepo.getEngagementValue('search_tags') ?? '[]';
    final sentiment = await _userRepo.getEngagementValue('recent_question_sentiment') ?? 'general_inquiry';
    final totalPrayers = await _userRepo.getEngagementValue('total_prayers_completed') ?? '0';
    final prayerStreak = await _userRepo.getEngagementValue('prayer_streak') ?? '0';

    final prompt = 'Generate a brief, beautiful, and inspiring Islamic moral reflection or story (150-250 words) suitable for a daily reflection card. Customize it for a user with these local metrics:\n'
        '- Total Ayahs Read: $totalAyahs\n'
        '- Reading Streak: $readingStreak days\n'
        '- Last Read Verse: Surah $lastReadSurah:$lastReadAyah (Topic: $lastReadTopic)\n'
        '- Recent Search Tags: $searchTags\n'
        '- Recent Chat Sentiment: $sentiment\n'
        '- Total Salat Completed: $totalPrayers\n'
        '- Salat Streak: $prayerStreak days\n\n'
        "Ensure the response is extremely gentle, wise, comforting, and authentic. Start with a title (e.g. 'Title: ...') and then write the story content. Do not include any HTML or extra formatting.";

    final stream = _llmService.generateResponseStream(prompt, '');
    final chunks = await stream.toList();
    return chunks.join().trim();
  }

  String _formatDate(DateTime dt) {
    final year = dt.year;
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
