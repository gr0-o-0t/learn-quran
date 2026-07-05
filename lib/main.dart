import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/models/kb_catalog.dart';
import 'core/theme/app_theme.dart';
import 'core/services/background_worker_service.dart';
import 'core/services/kb_download_service.dart';
import 'core/providers/database_provider.dart';
import 'core/providers/repository_providers.dart';
import 'data/local/db/knowledge_base_database.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/quran_reader_screen.dart';
import 'presentation/screens/qa_agent_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/screens/permissions_onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final kbPath = await KbDownloadService().localPathFor(kCurrentKb);
  KnowledgeBaseDatabase? initialKnowledgeBaseDatabase = await _openKnowledgeBaseDatabaseSafely(kbPath);
  // Best-effort: never let background-alarm setup delay or block app startup.
  unawaited(_scheduleBackgroundPrayerWorker());
  runApp(
    ProviderScope(
      overrides: [
        knowledgeBaseDatabaseProvider.overrideWith((ref) {
          // The very first build reuses the instance already opened (and
          // integrity-checked) above; every later rebuild — triggered by
          // `ref.invalidate(knowledgeBaseDatabaseProvider)` after Settings
          // downloads a fresh kb.db — re-opens from the same on-disk path,
          // picking up the new content. Riverpod closes the previous element
          // (via this onDispose) before running this again.
          final db = initialKnowledgeBaseDatabase ?? KnowledgeBaseDatabase.fromFile(kbPath);
          initialKnowledgeBaseDatabase = null;
          ref.onDispose(db.close);
          return db;
        }),
      ],
      child: const LearnQuranApp(),
    ),
  );
}

/// Opens the knowledge base database at [path], forcing an actual integrity
/// check so a corrupt on-disk file — e.g. one left over from a download bug,
/// or corrupted by anything else — surfaces here, inside `main()` before
/// `runApp()`, instead of crashing later deep inside the widget tree. If
/// opening or checking throws, the bad file is deleted and we retry once,
/// which then opens (or creates) a fresh, empty database instead. A bad
/// knowledge base file should never be able to brick app startup.
Future<KnowledgeBaseDatabase> _openKnowledgeBaseDatabaseSafely(String path) async {
  KnowledgeBaseDatabase? db;
  try {
    db = KnowledgeBaseDatabase.fromFile(path);
    // Drift opens the underlying file lazily on first use, so force that
    // now rather than letting a corrupt file surface unguarded later.
    // `PRAGMA quick_check` walks the actual b-tree structure, unlike a
    // trivial `SELECT 1` (which a file with a valid header but corrupted
    // page data would still pass).
    final result = await db.customSelect('PRAGMA quick_check').getSingle();
    if (result.read<String>('quick_check') != 'ok') {
      throw const FormatException('knowledge base failed quick_check');
    }
    return db;
  } catch (_) {
    await db?.close();
    final badFile = File(path);
    if (await badFile.exists()) {
      await badFile.delete();
    }
    return KnowledgeBaseDatabase.fromFile(path);
  }
}

Future<void> _scheduleBackgroundPrayerWorker() async {
  try {
    final worker = BackgroundWorkerService();
    await worker.initialize();
    await worker.scheduleDailyPrayerWorker();
    // Also run once immediately so notifications are populated right away,
    // instead of waiting up to 24h for the first periodic fire.
    await worker.triggerImmediateRecalculation();
  } catch (_) {
    // Ignore — e.g. platforms other than Android don't support this plugin.
  }
}

class LearnQuranApp extends StatelessWidget {
  const LearnQuranApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Learn Quran',
      theme: AppTheme.lightTheme,
      home: const _AppEntryGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Decides whether to show the one-time permissions onboarding flow or go
/// straight to [AppShell], based on the persisted
/// `permissions_onboarding_completed` flag.
class _AppEntryGate extends ConsumerStatefulWidget {
  const _AppEntryGate();

  @override
  ConsumerState<_AppEntryGate> createState() => _AppEntryGateState();
}

class _AppEntryGateState extends ConsumerState<_AppEntryGate> {
  bool _loading = true;
  bool _onboardingCompleted = false;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    // The permissions this flow requests (POST_NOTIFICATIONS, exact alarms)
    // are Android-only; skip straight to the app shell everywhere else.
    if (!Platform.isAndroid) {
      if (mounted) {
        setState(() {
          _onboardingCompleted = true;
          _loading = false;
        });
      }
      return;
    }

    final userRepo = ref.read(userRepositoryProvider);
    try {
      final completed = await userRepo
          .getEngagementValue('permissions_onboarding_completed');
      if (mounted) {
        setState(() {
          _onboardingCompleted = completed == 'true';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _onboardingCompleted = true; // fail open — never brick startup
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.softIvory,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.emeraldGreen),
        ),
      );
    }
    if (_onboardingCompleted) {
      return const AppShell();
    }
    return PermissionsOnboardingScreen(
      onFinished: () => setState(() => _onboardingCompleted = true),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _settingsTabIndex = 3;

  int _currentIndex = 0;

  void _switchToSettingsTab() => setState(() => _currentIndex = _settingsTabIndex);

  @override
  Widget build(BuildContext context) {
    // Not `static const`: QuranReaderScreen/QaAgentScreen need to know
    // whether they're the active tab (isActive) so they can re-check their
    // setup gate after the user downloads something from Settings without
    // leaving this IndexedStack — see onNavigateToSettings below, which
    // switches tabs instead of pushing a disconnected second SettingsScreen
    // (that duplicate used to silently orphan any in-progress download).
    final screens = [
      const DashboardScreen(),
      QuranReaderScreen(onNavigateToSettings: _switchToSettingsTab, isActive: _currentIndex == 1),
      QaAgentScreen(onNavigateToSettings: _switchToSettingsTab, isActive: _currentIndex == 2),
      const SettingsScreen(),
    ];
    return Scaffold(
      appBar: (_currentIndex == 2 || _currentIndex == 3)
          ? null
          : AppBar(
              title: Text(_titles[_currentIndex]),
              centerTitle: true,
            ),
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.softIvory,
        selectedItemColor: AppTheme.forestGreen,
        unselectedItemColor: AppTheme.textMuted,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book_rounded),
            label: 'Quran',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_rounded),
            label: 'Q&A',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  static const List<String> _titles = [
    'Learn Quran',
    'The Holy Quran',
    'Gentle Teacher',
    'Settings',
  ];
}
