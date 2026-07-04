# Permissions Onboarding UI — Design

## Problem

The daily Salat recalculation worker and prayer-time notifications depend on
two Android runtime-gated permissions that the app never requests:

- `POST_NOTIFICATIONS` (Android 13+/API 33+) — required to post any
  notification at all.
- Exact alarm scheduling (Android 12+/API 31+) — `NotificationService`
  schedules prayer reminders with `AndroidScheduleMode.exactAllowWhileIdle`,
  which silently no-ops without this.

Both permissions are declared in `AndroidManifest.xml` already, but nothing
in the app ever prompts the user to grant them, so prayer notifications can
silently never fire on real devices.

## Solution

A one-time, full-screen onboarding flow shown before the main app shell on
first launch, plus a fallback status card in Settings for anyone who skips
it. No new dependency — `flutter_local_notifications` 22.0.0 (already a
dependency) exposes everything needed via its Android-specific plugin
surface: `requestNotificationsPermission()`, `requestExactAlarmsPermission()`,
`areNotificationsEnabled()`, `canScheduleExactNotifications()`.

### Onboarding screen

New `lib/presentation/screens/permissions_onboarding_screen.dart`, styled
consistently with the rest of the app (`AppTheme` tokens, `google_fonts`):

- Bell icon, "Stay on Time for Salat" headline, one short paragraph in the
  app's established gentle/Sunnah tone (Rules.md) explaining that the app
  needs notification + precise-timing access to deliver prayer reminders.
- Primary button "Enable Prayer Reminders": calls, in sequence,
  `NotificationService.requestNotificationsPermission()` then
  `requestExactAlarmsPermission()`. The exact-alarm request opens Android's
  system settings screen directly (`ACTION_REQUEST_SCHEDULE_EXACT_ALARM`);
  this is fire-and-forget — the app does not block waiting for the user to
  return.
- Text button "Skip for now": requests nothing.
- **Both paths** persist `permissions_onboarding_completed = 'true'` via the
  existing `UserRepository` engagement key-value store and navigate to
  `AppShell`. Per the "never nag again" decision, this screen is not shown
  again automatically regardless of which path the user took — the Settings
  status card (below) is the only other way to grant later.

### Startup routing

`main.dart`'s `MaterialApp.home` changes from `const AppShell()` to a small
stateful gate widget (`_AppEntryGate` or similar) that, on `initState`, reads
`permissions_onboarding_completed` from `UserRepository` (one async read),
shows a brief loading state, then renders `PermissionsOnboardingScreen` or
`AppShell` accordingly. Non-Android platforms (there is currently no iOS
target scaffolded) skip straight to `AppShell` — the underlying permission
calls already no-op safely there, but there's no reason to show
Android-specific copy on a platform where these permissions don't apply.

### NotificationService additions

Four new thin wrapper methods around `AndroidFlutterLocalNotificationsPlugin`
(resolved via `resolvePlatformSpecificImplementation`), each returning
`Future<bool?>` and resolving to `null` safely if the Android-specific
implementation isn't available (non-Android, or a test VM):

- `requestNotificationsPermission()`
- `requestExactAlarmsPermission()`
- `areNotificationsEnabled()`
- `canScheduleExactNotifications()`

### Settings screen fallback

A compact "Permissions" card added to the existing `SettingsScreen`, showing
live status for both permissions (checked in `initState`/on resume) with a
"Grant" button next to whichever is missing. This re-checks status when the
screen's dependencies change (covers the case where a user goes to system
settings for exact alarms and comes back). This card is the *only* other way
to grant permissions once onboarding has been skipped, since onboarding
itself never reappears.

## Data flow

```
main() → _AppEntryGate reads permissions_onboarding_completed
  ├─ false/unset → PermissionsOnboardingScreen
  │     ├─ Enable → request both permissions (fire-and-forget) → set flag=true → AppShell
  │     └─ Skip   → set flag=true → AppShell
  └─ true → AppShell
              └─ SettingsScreen → Permissions card → re-check + grant-if-missing
```

## Error handling

- Permission request calls are wrapped so a `null`/failure result never
  throws or blocks navigation — the app always proceeds to `AppShell`
  regardless of what the user chose or whether the OS calls succeeded.
- No new manifest permissions needed; both are already declared.

## Testing

- `NotificationService`'s four new methods: unit-tested against a real
  (non-Android) `NotificationService()` instance, asserting they resolve to
  `null` rather than throwing — mirrors how the existing suite already tests
  mock/fallback paths in this dev environment.
- The onboarding screen and Settings status card are primarily static/wiring
  UI; no new widget-test infra is introduced for them (consistent with the
  rest of the codebase, which has no widget tests).

## Out of scope

- iOS equivalent (no iOS platform target exists yet).
- Waiting for/observing the user's actual return from the exact-alarm system
  settings screen during onboarding itself (only the Settings card re-checks
  on resume).
