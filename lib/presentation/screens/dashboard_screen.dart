import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:adhan/adhan.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/services/prayer_time_service.dart';
import '../../core/theme/quran_data.dart';
import '../../data/local/db/knowledge_base_database.dart';
import 'surah_detail_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _timer;
  
  // Salat checklist state
  Map<String, bool> _prayers = {
    'fajr': false,
    'dhuhr': false,
    'asr': false,
    'maghrib': false,
    'isha': false,
  };
  bool _loadingSalat = true;

  // Daily reflection state
  Verse? _reflectionVerse;
  bool _loadingReflection = true;

  // Daily story state (LLM-compiled, personalized to engagement history)
  String? _dailyStory;
  bool _loadingStory = true;

  // Calculation parameters from settings
  CalculationMethod _method = CalculationMethod.muslim_world_league;
  Madhab _madhab = Madhab.hanafi;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _loadData() async {
    await _loadSettings();
    await Future.wait([
      _loadSalatLog(),
      _loadReflectionVerse(),
    ]);
    // Don't block the rest of the dashboard on LLM generation.
    unawaited(_loadDailyStory());
  }

  Future<void> _loadSettings() async {
    try {
      final userRepo = ref.read(userRepositoryProvider);
      final methodStr = await userRepo.getEngagementValue('calculation_method') ?? 'muslim_world_league';
      final madhabStr = await userRepo.getEngagementValue('madhab') ?? 'hanafi';
      if (mounted) {
        setState(() {
          _method = _parseMethod(methodStr);
          _madhab = _parseMadhab(madhabStr);
        });
      }
    } catch (_) {}
  }

  CalculationMethod _parseMethod(String str) {
    switch (str) {
      case 'muslim_world_league':
        return CalculationMethod.muslim_world_league;
      case 'north_america':
        return CalculationMethod.north_america;
      case 'umm_al_qura':
        return CalculationMethod.umm_al_qura;
      case 'karachi':
        return CalculationMethod.karachi;
      case 'egyptian':
        return CalculationMethod.egyptian;
      default:
        return CalculationMethod.muslim_world_league;
    }
  }

  Madhab _parseMadhab(String str) {
    return str == 'hanafi' ? Madhab.hanafi : Madhab.shafi;
  }

  String _getTodayDateString() {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _loadSalatLog() async {
    try {
      final dateStr = _getTodayDateString();
      final userRepo = ref.read(userRepositoryProvider);
      final log = await userRepo.getSalatLogForDate(dateStr);
      if (mounted) {
        setState(() {
          if (log != null) {
            _prayers = {
              'fajr': log.fajrCompleted,
              'dhuhr': log.dhuhrCompleted,
              'asr': log.asrCompleted,
              'maghrib': log.maghribCompleted,
              'isha': log.ishaCompleted,
            };
          }
          _loadingSalat = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingSalat = false);
      }
    }
  }

  Future<void> _toggleSalat(String prayer, bool completed) async {
    try {
      final dateStr = _getTodayDateString();
      final userRepo = ref.read(userRepositoryProvider);
      await userRepo.updateSalatLog(dateStr, prayer, completed);
      if (mounted) {
        setState(() {
          _prayers[prayer] = completed;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadReflectionVerse() async {
    try {
      final now = DateTime.now();
      final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
      final surahNumber = (dayOfYear % 114) + 1;
      const ayahNumber = 1;

      final quranRepo = ref.read(quranRepositoryProvider);
      final verse = await quranRepo.getVerse(surahNumber, ayahNumber);

      if (mounted) {
        setState(() {
          _reflectionVerse = verse;
          _loadingReflection = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingReflection = false);
      }
    }
  }

  Future<void> _loadDailyStory() async {
    try {
      final story = await ref.read(dailyStoryServiceProvider).getOrCompileDailyStory();
      if (mounted) {
        setState(() {
          _dailyStory = story;
          _loadingStory = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingStory = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick search bar
            TextField(
              readOnly: true,
              onTap: () {
                // Switch to Q&A agent tab (index 2 in main scaffold, or let user type)
                DefaultTabController.of(context).animateTo(2);
              },
              decoration: InputDecoration(
                hintText: 'Search Quran, Hadith, or ask a question...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textMuted,
                ),
                prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surfaceMint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 24),

            // Next prayer card
            _buildNextPrayerCard(theme),
            const SizedBox(height: 16),

            // Salat checklist card
            _buildSalatChecklistCard(theme),
            const SizedBox(height: 16),

            // Daily reflection card
            _buildDailyReflectionCard(theme),
            const SizedBox(height: 16),

            // Daily story card (personalized, LLM-compiled)
            _buildDailyStoryCard(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildNextPrayerCard(ThemeData theme) {
    final prayerService = ref.watch(prayerTimeServiceProvider);
    final now = DateTime.now();
    final times = prayerService.calculatePrayerTimes(
      latitude: 21.4225,
      longitude: 39.8262,
      method: _method,
      madhab: _madhab,
      date: now,
    );

    String nextName = 'Fajr';
    DateTime nextTime = times.fajr;

    final next = times.nextPrayer();
    if (next == Prayer.none || next == Prayer.isha) {
      final tomorrowTimes = prayerService.calculatePrayerTimes(
        latitude: 21.4225,
        longitude: 39.8262,
        method: _method,
        madhab: _madhab,
        date: now.add(const Duration(days: 1)),
      );
      nextName = 'Fajr';
      nextTime = tomorrowTimes.fajr;
    } else if (next == Prayer.sunrise) {
      nextName = 'Dhuhr';
      nextTime = times.dhuhr;
    } else {
      nextName = _getPrayerDisplayName(next);
      nextTime = times.timeForPrayer(next) ?? now;
    }

    final timeStr = _formatTime(nextTime);
    final countdownStr = _formatCountdown(nextTime);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.forestGreen, AppTheme.emeraldGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next Prayer',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            nextName,
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$timeStr • $countdownStr',
            style: GoogleFonts.inter(
              fontSize: 16,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  String _getPrayerDisplayName(Prayer prayer) {
    switch (prayer) {
      case Prayer.fajr:
        return 'Fajr';
      case Prayer.dhuhr:
        return 'Dhuhr';
      case Prayer.asr:
        return 'Asr';
      case Prayer.maghrib:
        return 'Maghrib';
      case Prayer.isha:
        return 'Isha';
      default:
        return 'Fajr';
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:$minute $ampm';
  }

  String _formatCountdown(DateTime target) {
    final now = DateTime.now();
    final diff = target.difference(now);
    if (diff.isNegative) return 'now';
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    if (hours > 0) {
      return 'in ${hours}h ${minutes}m';
    } else {
      return 'in ${minutes}m';
    }
  }

  Widget _buildSalatChecklistCard(ThemeData theme) {
    if (_loadingSalat) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.surfaceMint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const CircularProgressIndicator(color: AppTheme.emeraldGreen),
      );
    }

    final displayNames = {
      'fajr': 'Fajr',
      'dhuhr': 'Dhuhr',
      'asr': 'Asr',
      'maghrib': 'Maghrib',
      'isha': 'Isha',
    };

    final completedCount = _prayers.values.where((v) => v).length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Today's Prayers", style: theme.textTheme.titleMedium),
              Text(
                '$completedCount/5 completed',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.emeraldGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._prayers.entries.map((entry) => CheckboxListTile(
                title: Text(displayNames[entry.key] ?? entry.key, style: theme.textTheme.bodyMedium),
                value: entry.value,
                activeColor: AppTheme.emeraldGreen,
                contentPadding: EdgeInsets.zero,
                dense: true,
                onChanged: (val) => _toggleSalat(entry.key, val ?? false),
              )),
        ],
      ),
    );
  }

  Widget _buildDailyReflectionCard(ThemeData theme) {
    if (_loadingReflection) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.surfaceMint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const CircularProgressIndicator(color: AppTheme.emeraldGreen),
      );
    }

    final verse = _reflectionVerse;
    if (verse == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceMint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text('No reflection available for today.', style: theme.textTheme.bodyMedium),
      );
    }

    final surahInfo = quranSurahs[verse.surahNumber - 1];
    final surahName = surahInfo['nameEn'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.accentGold.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_stories_rounded,
                  color: AppTheme.accentGold, size: 20),
              const SizedBox(width: 8),
              Text('Daily Reflection', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            verse.arabicText,
            style: AppTheme.arabicTextStyle.copyWith(fontSize: 22),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 8),
          Text(
            '— Surah $surahName (${verse.surahNumber}:${verse.ayahNumber})',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          Text(
            verse.englishText,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SurahDetailScreen(
                      surahNumber: verse.surahNumber,
                      surahName: surahName,
                      surahNameAr: surahInfo['nameAr'],
                    ),
                  ),
                );
              },
              child: const Text('Read More',
                  style: TextStyle(color: AppTheme.emeraldGreen)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyStoryCard(ThemeData theme) {
    if (_loadingStory) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.surfaceMint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const CircularProgressIndicator(color: AppTheme.emeraldGreen),
      );
    }

    final story = _dailyStory;
    if (story == null || story.isEmpty) {
      return const SizedBox.shrink();
    }

    String title = 'Your Daily Story';
    String body = story;
    final titleMatch = RegExp(r'^Title:\s*(.+)$', multiLine: true).firstMatch(story);
    if (titleMatch != null) {
      title = titleMatch.group(1)!.trim();
      body = story.replaceFirst(titleMatch.group(0)!, '').trim();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_rounded,
                  color: AppTheme.emeraldGreen, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
