import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/quran_data.dart';
import 'surah_detail_screen.dart';
import 'juz_detail_screen.dart';

class QuranReaderScreen extends StatelessWidget {
  const QuranReaderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: TabBar(
                labelColor: AppTheme.forestGreen,
                unselectedLabelColor: AppTheme.textMuted,
                indicatorColor: AppTheme.emeraldGreen,
                labelStyle: GoogleFonts.outfit(
                    fontSize: 16, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(text: 'Surah'),
                  Tab(text: 'Juz'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _SurahListView(),
                  _JuzListView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurahListView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: quranSurahs.length,
      itemBuilder: (context, index) {
        final surah = quranSurahs[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SurahDetailScreen(
                    surahNumber: surah['number'] as int,
                    surahName: surah['nameEn'] as String,
                    surahNameAr: surah['nameAr'] as String,
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceMint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  // Surah number circle
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.emeraldGreen.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${surah['number']}',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.emeraldGreen,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Surah info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          surah['nameEn'] as String,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${surah['type']} • ${surah['ayahs']} Ayahs',
                          style: theme.textTheme.labelLarge,
                        ),
                      ],
                    ),
                  ),
                  // Arabic name
                  Text(
                    surah['nameAr'] as String,
                    style: AppTheme.arabicTextStyle.copyWith(
                      fontSize: 20,
                      color: AppTheme.forestGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _JuzListView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: 30,
      itemBuilder: (context, index) {
        final juzNumber = index + 1;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => JuzDetailScreen(juzNumber: juzNumber),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceMint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.accentGold.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$juzNumber',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentGold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Juz $juzNumber',
                    style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
