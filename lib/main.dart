import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/services/background_worker_service.dart';
import 'core/providers/repository_providers.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/quran_reader_screen.dart';
import 'presentation/screens/qa_agent_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/screens/permissions_onboarding_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Best-effort: never let background-alarm setup delay or block app startup.
  unawaited(_scheduleBackgroundPrayerWorker());
  runApp(
    const ProviderScope(
      child: LearnQuranApp(),
    ),
  );
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
  int _currentIndex = 0;

  static const List<Widget> _screens = [
    DashboardScreen(),
    QuranReaderScreen(),
    QaAgentScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: (_currentIndex == 2 || _currentIndex == 3)
          ? null
          : AppBar(
              title: Text(_titles[_currentIndex]),
              centerTitle: true,
            ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
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
