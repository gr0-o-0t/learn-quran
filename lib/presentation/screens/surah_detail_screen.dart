import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/repository_providers.dart';
import '../../data/local/db/knowledge_base_database.dart';

class SurahDetailScreen extends ConsumerStatefulWidget {
  final int surahNumber;
  final String surahName;
  final String surahNameAr;

  const SurahDetailScreen({
    super.key,
    required this.surahNumber,
    required this.surahName,
    required this.surahNameAr,
  });

  @override
  ConsumerState<SurahDetailScreen> createState() => _SurahDetailScreenState();
}

class _SurahDetailScreenState extends ConsumerState<SurahDetailScreen> {
  int? _lastTrackedAyah;

  void _trackProgress(int ayahNumber) {
    if (_lastTrackedAyah == ayahNumber) return;
    _lastTrackedAyah = ayahNumber;
    ref.read(userRepositoryProvider).updateReadingProgress(widget.surahNumber, ayahNumber);
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
        title: Column(
          children: [
            Text(widget.surahName, style: theme.textTheme.titleMedium),
            Text(
              widget.surahNameAr,
              style: AppTheme.arabicTextStyle.copyWith(
                fontSize: 16,
                color: AppTheme.emeraldGreen,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Verse>>(
        future: ref.read(quranRepositoryProvider).getVersesBySurah(widget.surahNumber),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.emeraldGreen));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error loading verses: ${snapshot.error}'));
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
                    'No verses found in database',
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
              
              // Track reading progress on scroll (when verse card is built)
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _trackProgress(verse.ayahNumber);
              });

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GestureDetector(
                  onTap: () {
                    _trackProgress(verse.ayahNumber);
                  },
                  onLongPress: () {
                    _showTafsirBottomSheet(context, widget.surahNumber, verse.ayahNumber);
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
                        // Ayah number badge and actions
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppTheme.accentGold.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${verse.ayahNumber}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.accentGold,
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.bookmark_border_rounded, size: 20),
                                  color: AppTheme.textMuted,
                                  onPressed: () {
                                    ref.read(userRepositoryProvider).toggleBookmark(
                                      widget.surahNumber,
                                      verse.ayahNumber,
                                      'General',
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Ayah ${verse.ayahNumber} bookmarked.'),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.play_circle_outline, size: 20),
                                  color: AppTheme.textMuted,
                                  onPressed: () {
                                    // Keep as no-op or minor feedback
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
