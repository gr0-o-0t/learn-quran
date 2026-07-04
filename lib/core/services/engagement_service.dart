import 'dart:convert';
import '../../data/local/db/app_database.dart';
import '../../data/repositories/quran_repository.dart';
import '../../data/repositories/user_repository.dart';

class EngagementService {
  final UserRepository _userRepo;
  final QuranRepository _quranRepo;

  EngagementService(this._userRepo, this._quranRepo);

  /// Logs a reading event, updating total ayahs read, last read surah/ayah,
  /// last read topic (derived from verse text), last read timestamp, and reading streak.
  Future<void> logReadingEvent(int surah, int ayah) async {
    // 1. Update total_ayahs_read
    final totalAyahsStr = await _userRepo.getEngagementValue('total_ayahs_read') ?? '0';
    final totalAyahs = int.parse(totalAyahsStr) + 1;
    await _userRepo.setEngagementValue('total_ayahs_read', totalAyahs.toString());

    // 2. Set last_read_surah and last_read_ayah
    await _userRepo.setEngagementValue('last_read_surah', surah.toString());
    await _userRepo.setEngagementValue('last_read_ayah', ayah.toString());

    // 3. Set last_read_timestamp
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _userRepo.setEngagementValue('last_read_timestamp', nowMs.toString());

    // 4. Update reading streak
    final lastReadDateStr = await _userRepo.getEngagementValue('last_read_date');
    final today = DateTime.now();
    final todayStr = _formatDate(today);
    
    if (lastReadDateStr == null) {
      await _userRepo.setEngagementValue('reading_streak', '1');
      await _userRepo.setEngagementValue('last_read_date', todayStr);
    } else if (lastReadDateStr != todayStr) {
      final lastReadDate = DateTime.parse(lastReadDateStr);
      final difference = today.difference(lastReadDate).inDays;
      if (difference == 1) {
        final currentStreakStr = await _userRepo.getEngagementValue('reading_streak') ?? '0';
        final newStreak = int.parse(currentStreakStr) + 1;
        await _userRepo.setEngagementValue('reading_streak', newStreak.toString());
      } else if (difference > 1) {
        await _userRepo.setEngagementValue('reading_streak', '1');
      }
      await _userRepo.setEngagementValue('last_read_date', todayStr);
    }

    // 5. Update last_read_topic by looking up verse translation keywords
    final verse = await _quranRepo.getVerse(surah, ayah);
    if (verse != null) {
      final topic = _detectTopic(verse.englishText);
      await _userRepo.setEngagementValue('last_read_topic', topic);
    }
  }

  /// Logs a search or question query, updating last search query, recent question sentiment,
  /// and search tags (a JSON array of unique topics explored).
  Future<void> logSearchEvent(String query) async {
    await _userRepo.setEngagementValue('last_search_query', query);
    
    // Extract topic tags
    final topic = _detectTopic(query);
    final existingTagsStr = await _userRepo.getEngagementValue('search_tags') ?? '[]';
    List<String> tags = [];
    try {
      tags = List<String>.from(jsonDecode(existingTagsStr));
    } catch (_) {}
    if (!tags.contains(topic)) {
      tags.add(topic);
      if (tags.length > 5) {
        tags.removeAt(0); // keep last 5
      }
      await _userRepo.setEngagementValue('search_tags', jsonEncode(tags));
    }

    // Detect sentiment
    final sentiment = _detectSentiment(query);
    await _userRepo.setEngagementValue('recent_question_sentiment', sentiment);
  }

  /// Compiles prayer metrics based on all local SalatLogs: updates total prayers completed,
  /// and calculates prayer streak.
  Future<void> compileSalatMetrics() async {
    final logs = await _userRepo.getAllSalatLogs();
    
    final totalCompleted = _calculateTotalCompletedPrayers(logs);
    final streak = _calculatePrayerStreak(logs);

    await _userRepo.setEngagementValue('total_prayers_completed', totalCompleted.toString());
    await _userRepo.setEngagementValue('prayer_streak', streak.toString());
    
    final today = DateTime.now();
    await _userRepo.setEngagementValue('last_logged_prayer_date', _formatDate(today));
  }

  String _formatDate(DateTime dt) {
    final year = dt.year;
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  bool _isAnyCompleted(SalatLog log) {
    return log.fajrCompleted || log.dhuhrCompleted || log.asrCompleted || log.maghribCompleted || log.ishaCompleted;
  }

  int _calculateTotalCompletedPrayers(List<SalatLog> logs) {
    int count = 0;
    for (final log in logs) {
      if (log.fajrCompleted) count++;
      if (log.dhuhrCompleted) count++;
      if (log.asrCompleted) count++;
      if (log.maghribCompleted) count++;
      if (log.ishaCompleted) count++;
    }
    return count;
  }

  int _calculatePrayerStreak(List<SalatLog> logs) {
    if (logs.isEmpty) return 0;
    final today = DateTime.now();
    final todayStr = _formatDate(today);
    final yesterdayStr = _formatDate(today.subtract(const Duration(days: 1)));

    bool hasRecent = false;
    for (final log in logs) {
      if (_isAnyCompleted(log) && (log.date == todayStr || log.date == yesterdayStr)) {
        hasRecent = true;
        break;
      }
    }
    if (!hasRecent) return 0;

    final logMap = {for (var log in logs) log.date: log};
    
    int streak = 0;
    DateTime checkDate = logMap.containsKey(todayStr) && _isAnyCompleted(logMap[todayStr]!) 
        ? today 
        : today.subtract(const Duration(days: 1));
        
    while (true) {
      final checkDateStr = _formatDate(checkDate);
      final log = logMap[checkDateStr];
      if (log != null && _isAnyCompleted(log)) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  String _detectTopic(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('patience') || lower.contains('sabr') || lower.contains('steadfast')) {
      return 'patience';
    }
    if (lower.contains('parent') || lower.contains('father') || lower.contains('mother') || lower.contains('family')) {
      return 'parents';
    }
    if (lower.contains('forgive') || lower.contains('forgiveness') || lower.contains('pardon')) {
      return 'forgiveness';
    }
    if (lower.contains('mercy') || lower.contains('merciful') || lower.contains('compassion')) {
      return 'mercy';
    }
    if (lower.contains('prayer') || lower.contains('salat') || lower.contains('pray') || lower.contains('prostrate')) {
      return 'prayer';
    }
    if (lower.contains('charity') || lower.contains('zakat') || lower.contains('give') || lower.contains('spend')) {
      return 'charity';
    }
    if (lower.contains('fasting') || lower.contains('sawm') || lower.contains('fast') || lower.contains('ramadan')) {
      return 'fasting';
    }
    if (lower.contains('gratitude') || lower.contains('shukr') || lower.contains('thank') || lower.contains('grateful')) {
      return 'gratitude';
    }
    if (lower.contains('knowledge') || lower.contains('learn') || lower.contains('read') || lower.contains('wisdom')) {
      return 'knowledge';
    }
    return 'general';
  }

  String _detectSentiment(String query) {
    final lower = query.toLowerCase();
    if (lower.contains('sad') ||
        lower.contains('grief') ||
        lower.contains('sorrow') ||
        lower.contains('depress') ||
        lower.contains('anxious') ||
        lower.contains('anxiety') ||
        lower.contains('fear') ||
        lower.contains('scared') ||
        lower.contains('difficult') ||
        lower.contains('pain') ||
        lower.contains('struggle')) {
      return 'seeking_comfort';
    }
    if (lower.contains('how') ||
        lower.contains('what') ||
        lower.contains('rule') ||
        lower.contains('obligation') ||
        lower.contains('permissible') ||
        lower.contains('halal') ||
        lower.contains('haram') ||
        lower.contains('why') ||
        lower.contains('can i') ||
        lower.contains('ruling')) {
      return 'seeking_knowledge';
    }
    if (lower.contains('thank') ||
        lower.contains('grateful') ||
        lower.contains('blessing') ||
        lower.contains('happy') ||
        lower.contains('praise') ||
        lower.contains('alhamdulillah')) {
      return 'gratitude';
    }
    return 'general_inquiry';
  }
}
