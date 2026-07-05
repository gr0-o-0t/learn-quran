import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/theme/quran_data.dart';
import '../../data/local/db/knowledge_base_database.dart';

class JuzDetailScreen extends ConsumerStatefulWidget {
  final int juzNumber;

  const JuzDetailScreen({
    super.key,
    required this.juzNumber,
  });

  @override
  ConsumerState<JuzDetailScreen> createState() => _JuzDetailScreenState();
}

class _JuzDetailScreenState extends ConsumerState<JuzDetailScreen> {
  int? _lastTrackedAyah;
  int? _lastTrackedSurah;

  void _trackProgress(int surahNumber, int ayahNumber) {
    if (_lastTrackedSurah == surahNumber && _lastTrackedAyah == ayahNumber) return;
    _lastTrackedSurah = surahNumber;
    _lastTrackedAyah = ayahNumber;
    ref.read(userRepositoryProvider).updateReadingProgress(surahNumber, ayahNumber);
    ref.read(engagementServiceProvider).logReadingEvent(surahNumber, ayahNumber);
  }

  void _showTafsirBottomSheet(BuildContext context, int surahNum, int ayahNum) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppTheme.softIvory,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: FutureBuilder<List<Tafsir>>(
                future: ref.read(quranRepositoryProvider).getTafsirForVerse(surahNum, ayahNum),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppTheme.emeraldGreen));
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading Tafsir: ${snapshot.error}'));
                  }
                  final tafsirs = snapshot.data ?? [];
                  if (tafsirs.isEmpty) {
                    return const Center(child: Text('No Tafsir available for this verse.'));
                  }

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(24),
                    itemCount: tafsirs.length,
                    itemBuilder: (context, index) {
                      final tafsir = tafsirs[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (index == 0) ...[
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: AppTheme.textMuted.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            Text(
                              'Tafsir (Surah $surahNum, Ayah $ayahNum)',
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.forestGreen,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Author: ${tafsir.author}',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                color: AppTheme.textMuted,
                              ),
                            ),
                            const Divider(height: 24),
                          ],
                          Text(
                            tafsir.contentEnglish,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              height: 1.6,
                              color: AppTheme.textCharcoal,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Juz ${widget.juzNumber}', style: theme.textTheme.titleMedium),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Verse>>(
        future: ref.read(quranRepositoryProvider).getVersesByJuz(widget.juzNumber),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.emeraldGreen));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error loading Juz verses: ${snapshot.error}'));
          }
          final verses = snapshot.data ?? [];
          if (verses.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.menu_book_rounded,
                      size: 64, color: AppTheme.textMuted.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text(
                    'No verses found in this Juz',
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            itemCount: verses.length,
            itemBuilder: (context, index) {
              final verse = verses[index];
              final surahInfo = quranSurahs[verse.surahNumber - 1];
              final surahName = surahInfo['nameEn'];

              // Track reading progress on scroll
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _trackProgress(verse.surahNumber, verse.ayahNumber);
              });

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GestureDetector(
                  onTap: () {
                    _trackProgress(verse.surahNumber, verse.ayahNumber);
                  },
                  onLongPress: () {
                    _showTafsirBottomSheet(context, verse.surahNumber, verse.ayahNumber);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceMint,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header with surah name, number, and actions
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$surahName • ${verse.surahNumber}:${verse.ayahNumber}',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accentGold,
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.bookmark_border_rounded, size: 20),
                                  color: AppTheme.textMuted,
                                  onPressed: () {
                                    ref.read(userRepositoryProvider).toggleBookmark(
                                      verse.surahNumber,
                                      verse.ayahNumber,
                                      'Juz ${widget.juzNumber}',
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Ayah ${verse.surahNumber}:${verse.ayahNumber} bookmarked.'),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.play_circle_outline, size: 20),
                                  color: AppTheme.textMuted,
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Audio playing is coming soon.'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Arabic text
                        Text(
                          verse.arabicText,
                          style: AppTheme.arabicTextStyle,
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                        ),
                        const SizedBox(height: 16),
                        // Divider
                        Divider(
                          color: AppTheme.textMuted.withValues(alpha: 0.15),
                          height: 1,
                        ),
                        const SizedBox(height: 12),
                        // Translation
                        Text(
                          verse.englishText,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
