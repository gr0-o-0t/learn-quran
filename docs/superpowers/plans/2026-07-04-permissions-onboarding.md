# Permissions Onboarding UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a one-time onboarding screen that requests the two Android runtime permissions prayer notifications depend on (POST_NOTIFICATIONS, exact-alarm scheduling), plus a Settings fallback for anyone who skips it.

**Architecture:** `NotificationService` gains four thin wrapper methods around `AndroidFlutterLocalNotificationsPlugin`'s existing permission API (already part of the `flutter_local_notifications` 22.0.0 dependency — no new package). A new `PermissionsOnboardingScreen` calls them and persists completion via the existing `UserRepository` key-value store. `main.dart` gains a small gate widget that reads that flag at startup and picks `PermissionsOnboardingScreen` or `AppShell`. `SettingsScreen` gains a status card using the same service methods.

**Tech Stack:** Flutter, Riverpod (`ConsumerStatefulWidget`), `flutter_local_notifications` 22.0.0 (already a dependency), existing `UserRepository` engagement key-value store.

## Global Constraints

- No new dependency — `flutter_local_notifications` 22.0.0 already exposes everything needed.
- All new/changed user-facing copy must use the app's established gentle, non-clinical tone (Rules.md's "Sunnah Teaching Methodology").
- Permission request failures must never throw uncaught or block navigation — the app always proceeds regardless of what the OS returns.
- Once onboarding completes (Enable or Skip), it must never be shown again automatically — the Settings card is the only other path to grant.
- Android-only for now — no iOS platform target is scaffolded in this repo.
- `flutter analyze` must stay at zero `error`-level issues; `flutter test` must stay fully green.

---

### Task 1: Add permission wrapper methods to NotificationService

**Files:**
- Modify: `lib/core/services/notification_service.dart`
- Test: `test/core/services/notification_service_test.dart`

**Interfaces:**
- Consumes: `AndroidFlutterLocalNotificationsPlugin` (from the already-imported `package:flutter_local_notifications/flutter_local_notifications.dart`), via `FlutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<T>()`.
- Produces (used by Tasks 2 and 4):
  - `Future<bool?> NotificationService.requestNotificationsPermission()`
  - `Future<bool?> NotificationService.requestExactAlarmsPermission()`
  - `Future<bool?> NotificationService.areNotificationsEnabled()`
  - `Future<bool?> NotificationService.canScheduleExactNotifications()`
  - All four resolve to `null` (never throw) when the Android-specific plugin implementation isn't available — e.g. this dev machine's `flutter test` runs as `TargetPlatform.linux`, so `resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()` returns `null` and these methods short-circuit via `?.`.

- [ ] **Step 1: Write the failing tests**

Open `test/core/services/notification_service_test.dart` and add this new group at the end of `main()`, right before the final closing `});` of the outer `group('NotificationService Tests', ...)` — i.e. as a sibling top-level `group` call after it, inside `main()`:

```dart
  group('Permission methods on non-Android (real plugin)', () {
    test('requestNotificationsPermission returns null off Android', () async {
      final realService = NotificationService();
      final result = await realService.requestNotificationsPermission();
      expect(result, isNull);
    });

    test('requestExactAlarmsPermission returns null off Android', () async {
      final realService = NotificationService();
      final result = await realService.requestExactAlarmsPermission();
      expect(result, isNull);
    });

    test('areNotificationsEnabled returns null off Android', () async {
      final realService = NotificationService();
      final result = await realService.areNotificationsEnabled();
      expect(result, isNull);
    });

    test('canScheduleExactNotifications returns null off Android', () async {
      final realService = NotificationService();
      final result = await realService.canScheduleExactNotifications();
      expect(result, isNull);
    });
  });
```

This uses the real `NotificationService()` constructor (not the `.withPlugin` fake used by the existing tests in this file), because the behavior under test is the real plugin's platform-resolution logic returning `null` off Android — the fake plugin doesn't model that.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/services/notification_service_test.dart`
Expected: FAIL to compile — `The method 'requestNotificationsPermission' isn't defined for the type 'NotificationService'` (and similarly for the other three).

- [ ] **Step 3: Implement the four methods**

In `lib/core/services/notification_service.dart`, add these methods to the `NotificationService` class, right after `cancelNotification` and before the closing `}` of the class:

```dart
  /// Requests the POST_NOTIFICATIONS runtime permission (Android 13+).
  /// Returns null on platforms where the Android-specific implementation
  /// isn't available.
  Future<bool?> requestNotificationsPermission() async {
    return _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Requests exact-alarm scheduling access (Android 12+). This opens the
  /// system settings screen rather than an in-app dialog. Returns null on
  /// platforms where the Android-specific implementation isn't available.
  Future<bool?> requestExactAlarmsPermission() async {
    return _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
  }

  /// Whether notifications are currently enabled for this app. Returns null
  /// on platforms where the Android-specific implementation isn't available.
  Future<bool?> areNotificationsEnabled() async {
    return _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.areNotificationsEnabled();
  }

  /// Whether this app can currently schedule exact alarms. Returns null on
  /// platforms where the Android-specific implementation isn't available.
  Future<bool?> canScheduleExactNotifications() async {
    return _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.canScheduleExactNotifications();
  }
```

No new import is needed — `AndroidFlutterLocalNotificationsPlugin` is already exported from the `package:flutter_local_notifications/flutter_local_notifications.dart` import at the top of this file.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/core/services/notification_service_test.dart`
Expected: PASS — all tests in the file green (the 4 pre-existing tests plus the 4 new ones).

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze lib/core/services/notification_service.dart test/core/services/notification_service_test.dart`
Expected: `No issues found!`

```bash
git add lib/core/services/notification_service.dart test/core/services/notification_service_test.dart
git commit -m "feat: add permission wrapper methods to NotificationService"
```

---

### Task 2: Build the PermissionsOnboardingScreen

**Files:**
- Create: `lib/presentation/screens/permissions_onboarding_screen.dart`

**Interfaces:**
- Consumes: `NotificationService.requestNotificationsPermission()`, `NotificationService.requestExactAlarmsPermission()` (Task 1); `notificationServiceProvider` (`lib/core/services/notification_service.dart`); `userRepositoryProvider` (`lib/core/providers/repository_providers.dart`); `UserRepository.setEngagementValue(String, String)` (existing); `AppTheme` tokens `forestGreen`, `emeraldGreen`, `softIvory`, `textMuted` (`lib/core/theme/app_theme.dart`).
- Produces (used by Task 3): `PermissionsOnboardingScreen({required VoidCallback onFinished})` — a widget that, once the user picks Enable or Skip, persists `permissions_onboarding_completed = 'true'` via `UserRepository` and then calls `onFinished`. It does not navigate itself and has no knowledge of `AppShell`.

- [ ] **Step 1: Write the screen**

Create `lib/presentation/screens/permissions_onboarding_screen.dart`:

```dart
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
                "Learn Quran would like to send you gentle reminders for "
                "each prayer time, precisely when they begin. Please allow "
                "notifications and precise timing so your reminders arrive "
                "exactly when they should, insha'Allah.",
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
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/presentation/screens/permissions_onboarding_screen.dart`
Expected: `No issues found!`

There is no widget-test infrastructure anywhere else in this codebase (it's absent from every other screen too), so this task's verification is `flutter analyze` only — consistent with the rest of the project.

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/screens/permissions_onboarding_screen.dart
git commit -m "feat: add PermissionsOnboardingScreen"
```

---

### Task 3: Wire the onboarding gate into main.dart

**Files:**
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `PermissionsOnboardingScreen` (Task 2); `userRepositoryProvider` (`lib/core/providers/repository_providers.dart`); `UserRepository.getEngagementValue(String)` (existing); `AppShell` (already defined in this file).
- Produces: nothing consumed by later tasks — this is the top of the widget tree.

- [ ] **Step 1: Add imports**

In `lib/main.dart`, add these two imports alongside the existing screen imports:

```dart
import 'core/providers/repository_providers.dart';
import 'presentation/screens/permissions_onboarding_screen.dart';
```

- [ ] **Step 2: Point MaterialApp.home at the new gate widget**

Change:

```dart
      home: const AppShell(),
```

to:

```dart
      home: const _AppEntryGate(),
```

- [ ] **Step 3: Add the `_AppEntryGate` widget**

Add this new class in `lib/main.dart`, after the `LearnQuranApp` class and before the `AppShell` class:

```dart
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
    final completed = await userRepo
        .getEngagementValue('permissions_onboarding_completed');
    if (mounted) {
      setState(() {
        _onboardingCompleted = completed == 'true';
        _loading = false;
      });
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
```

- [ ] **Step 4: Analyze and run the full test suite**

Run: `flutter analyze lib/main.dart`
Expected: `No issues found!`

Run: `flutter test`
Expected: all tests pass (this change touches app startup wiring only; no existing test imports `main.dart`, so none should be affected).

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "feat: gate app startup on permissions onboarding"
```

---

### Task 4: Add a Permissions status card to SettingsScreen

**Files:**
- Modify: `lib/presentation/screens/settings_screen.dart`

**Interfaces:**
- Consumes: `NotificationService.areNotificationsEnabled()`, `canScheduleExactNotifications()`, `requestNotificationsPermission()`, `requestExactAlarmsPermission()` (Task 1); `notificationServiceProvider` (already imported in this file); the existing private `_buildSectionCard({required ThemeData theme, required String title, required IconData icon, required List<Widget> children})` helper already defined in this file.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add `WidgetsBindingObserver` and permission state**

Change the class declaration from:

```dart
class _SettingsScreenState extends ConsumerState<SettingsScreen> {
```

to:

```dart
class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
```

Add these fields alongside the existing ones (`_selectedLanguage`, etc.):

```dart
  bool _notificationsEnabled = false;
  bool _exactAlarmsEnabled = false;
  bool _checkingPermissions = true;
```

- [ ] **Step 2: Hook lifecycle observation and add the permission-checking methods**

Replace:

```dart
  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadSettings());
  }
```

with:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => _loadSettings());
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches the user coming back from the exact-alarm system settings
    // screen, which flutter_local_notifications opens outside the app.
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final notifService = ref.read(notificationServiceProvider);
    final notifsEnabled = await notifService.areNotificationsEnabled();
    final exactAlarmsEnabled =
        await notifService.canScheduleExactNotifications();
    if (mounted) {
      setState(() {
        _notificationsEnabled = notifsEnabled ?? false;
        _exactAlarmsEnabled = exactAlarmsEnabled ?? false;
        _checkingPermissions = false;
      });
    }
  }

  Future<void> _grantNotifications() async {
    await ref
        .read(notificationServiceProvider)
        .requestNotificationsPermission();
    await _checkPermissions();
  }

  Future<void> _grantExactAlarms() async {
    await ref
        .read(notificationServiceProvider)
        .requestExactAlarmsPermission();
    await _checkPermissions();
  }
```

- [ ] **Step 3: Insert the Permissions card into `build()`**

Right after:

```dart
            Text('Settings', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 24),
```

and before the `// Language & Translation` comment, insert:

```dart
            if (!_checkingPermissions &&
                (!_notificationsEnabled || !_exactAlarmsEnabled)) ...[
              _buildSectionCard(
                theme: theme,
                title: 'Permissions',
                icon: Icons.verified_user_rounded,
                children: [
                  if (!_notificationsEnabled)
                    ListTile(
                      title: Text('Prayer Notifications',
                          style: theme.textTheme.bodyMedium),
                      subtitle: Text('Needed to show Salat reminders.',
                          style: theme.textTheme.labelLarge),
                      trailing: TextButton(
                        onPressed: _grantNotifications,
                        child: const Text('Grant'),
                      ),
                    ),
                  if (!_exactAlarmsEnabled)
                    ListTile(
                      title: Text('Precise Reminder Timing',
                          style: theme.textTheme.bodyMedium),
                      subtitle: Text(
                          'Needed for reminders to arrive exactly on time.',
                          style: theme.textTheme.labelLarge),
                      trailing: TextButton(
                        onPressed: _grantExactAlarms,
                        child: const Text('Grant'),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
```

This uses the existing `_buildSectionCard` helper already defined at the bottom of this file, so no new container styling is introduced. When both permissions are already granted, `_checkingPermissions` is `false` and both booleans are `true`, so the whole `if` is `false` and nothing renders — the card only appears when there's something to grant.

- [ ] **Step 4: Analyze and run the full test suite**

Run: `flutter analyze lib/presentation/screens/settings_screen.dart`
Expected: `No issues found!`

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/settings_screen.dart
git commit -m "feat: add permissions status card to Settings"
```

---

### Task 5: Final verification and release build

**Files:**
- Modify: `Tracker.md`

**Interfaces:**
- Consumes: nothing new — this task only verifies Tasks 1-4 together and produces a release artifact.

- [ ] **Step 1: Full analyze**

Run: `flutter analyze`
Expected: exit may be non-zero due to pre-existing `info`-level lints (documented in earlier work on this project), but zero `error`-level issues. Verify with:

Run: `flutter analyze 2>&1 | grep ' error •'`
Expected: no output (zero matches).

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all tests pass, including the 4 new tests from Task 1.

- [ ] **Step 3: Release build**

Run: `ANDROID_HOME="$HOME/Android/Sdk" flutter build apk --release`
Expected: `✓ Built build/app/outputs/flutter-apk/app-release.apk (...)` with no new warnings introduced by this feature.

Verify the new manifest permissions are unaffected (already present from earlier work) and the APK is still correctly signed:

Run: `"$HOME/Android/Sdk/build-tools/36.0.0/apksigner" verify --print-certs build/app/outputs/flutter-apk/app-release.apk`
Expected: prints the `CN=Learn Quran Dev` signer certificate, matching prior builds.

- [ ] **Step 4: Update Tracker.md**

`Tracker.md` doesn't have a dedicated task for this feature (it was scoped and built after the original 8-phase plan completed). Add a short new entry documenting it, appended after the existing Phase 8 section:

```markdown

### Phase 9: Permissions Onboarding
*   [x] **Task 9.1:** Build one-time permissions onboarding flow (notifications + exact-alarm scheduling) and a Settings fallback status card. (Completed: 2026-07-04)
    See design: [docs/superpowers/specs/2026-07-04-permissions-onboarding-design.md](docs/superpowers/specs/2026-07-04-permissions-onboarding-design.md)
```

- [ ] **Step 5: Commit**

```bash
git add Tracker.md
git commit -m "docs: mark permissions onboarding feature complete in Tracker"
```
