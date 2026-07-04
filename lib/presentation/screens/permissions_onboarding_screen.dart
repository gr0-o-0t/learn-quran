import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/services/notification_service.dart';

/// One-time onboarding screen requesting the notification and exact-alarm
/// permissions prayer reminders depend on. Shown by `_AppEntryGate` in
/// main.dart before `AppShell`, until `permissions_onboarding_completed` is
/// set to 'true'.
class PermissionsOnboardingScreen extends ConsumerStatefulWidget {
  const PermissionsOnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  ConsumerState<PermissionsOnboardingScreen> createState() =>
      _PermissionsOnboardingScreenState();
}

class _PermissionsOnboardingScreenState
    extends ConsumerState<PermissionsOnboardingScreen> {
  bool _isRequesting = false;

  Future<void> _finish() async {
    final userRepo = ref.read(userRepositoryProvider);
    await userRepo.setEngagementValue(
        'permissions_onboarding_completed', 'true');
    widget.onFinished();
  }

  Future<void> _enableReminders() async {
    setState(() => _isRequesting = true);
    final notifService = ref.read(notificationServiceProvider);
    try {
      await notifService.requestNotificationsPermission();
      await notifService.requestExactAlarmsPermission();
    } catch (_) {
      // Never let a permission-call failure block onboarding.
    } finally {
      await _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softIvory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.notifications_active_rounded,
                size: 72,
                color: AppTheme.emeraldGreen,
              ),
              const SizedBox(height: 24),
              Text(
                'Stay on Time for Salat',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.forestGreen,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Learn Quran would like to send you gentle reminders for '
                'each prayer time, precisely when they begin. Please allow '
                'notifications and precise timing so your reminders arrive '
                'exactly when they should, insha\'Allah.',
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
                  onPressed: _isRequesting ? null : _enableReminders,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.emeraldGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isRequesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Enable Prayer Reminders'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isRequesting ? null : _finish,
                child: const Text(
                  'Skip for now',
                  style: TextStyle(color: AppTheme.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
