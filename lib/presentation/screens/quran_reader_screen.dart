import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/quran_data.dart';
import '../../core/providers/repository_providers.dart';
import 'surah_detail_screen.dart';
import 'juz_detail_screen.dart';

/// Engagement-value key: once the user dismisses the knowledge-base setup
/// prompt (or finishes it with the knowledge base downloaded), this screen
/// stops re-showing it.
const kbSetupPromptDismissedKey = 'kb_setup_prompt_dismissed';

/// True if the "set up the knowledge base" prompt should be shown instead
/// of Quran content: the KB has no rows yet (nothing downloaded) and the
/// user hasn't already dismissed the prompt (dismissedFlag isn't 'true').
bool needsKbSetupPrompt({required bool hasContent, required String? dismissedFlag}) {
  return !hasContent && dismissedFlag != 'true';
}

class QuranReaderScreen extends ConsumerStatefulWidget {
  const QuranReaderScreen({super.key, required this.onNavigateToSettings, required this.isActive});

  /// Switches AppShell's bottom-nav selection to the Settings tab, reusing
  /// its single long-lived instance (and any download already in progress
  /// on it) instead of pushing a disconnected new one — see the "moving to
  /// another page halts the download" bug this replaced.
  final VoidCallback onNavigateToSettings;

  /// True while this is AppShell's currently selected tab. Lets this screen
  /// detect "the user came back to this tab" (e.g. after downloading the
  /// knowledge base from Settings) so the setup gate can re-check itself,
  /// since switching tabs doesn't re-run `initState`.
  final bool isActive;

  @override
  ConsumerState<QuranReaderScreen> createState() => _QuranReaderScreenState();
}

class _QuranReaderScreenState extends ConsumerState<QuranReaderScreen> {
  bool _checkingKbSetup = true;
  bool _needsKbSetup = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _checkKbSetup());
  }

  @override
  void didUpdateWidget(QuranReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _checkKbSetup();
    }
  }

  Future<void> _checkKbSetup() async {
    final quranRepo = ref.read(quranRepositoryProvider);
    final userRepo = ref.read(userRepositoryProvider);
    final hasContent = await quranRepo.hasContent();
    final dismissed = await userRepo.getEngagementValue(kbSetupPromptDismissedKey);
    if (mounted) {
      setState(() {
        _needsKbSetup = needsKbSetupPrompt(hasContent: hasContent, dismissedFlag: dismissed);
        _checkingKbSetup = false;
      });
    }
  }

  Future<void> _skipKbSetup() async {
    final userRepo = ref.read(userRepositoryProvider);
    await userRepo.setEngagementValue(kbSetupPromptDismissedKey, 'true');
    if (mounted) setState(() => _needsKbSetup = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingKbSetup) {
      return const SafeArea(
        child: Center(child: CircularProgressIndicator(color: AppTheme.emeraldGreen)),
      );
    }
    if (_needsKbSetup) {
      return _KbSetupPrompt(onSetUp: widget.onNavigateToSettings, onSkip: _skipKbSetup);
    }

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

class _KbSetupPrompt extends StatelessWidget {
  const _KbSetupPrompt({required this.onSetUp, required this.onSkip});

  final VoidCallback onSetUp;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.menu_book_rounded,
              size: 72,
              color: AppTheme.emeraldGreen,
            ),
            const SizedBox(height: 24),
            Text(
              'Set Up Your Knowledge Base',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.forestGreen,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Download the Quran, Hadith, and Tafsir content in Settings '
              'so you can read and search it here. This is a one-time '
              'download.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: AppTheme.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onSetUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.emeraldGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Set Up Knowledge Base'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onSkip,
              child: const Text(
                'Skip for now',
                style: TextStyle(color: AppTheme.textMuted),
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
