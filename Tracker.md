# Project Progress Tracker (Tracker) - Learn Quran Offline Mobile App

This file is updated dynamically to reflect the completion status of all tasks. 

---

## 1. Project Initialization & Planning (Current Phase)

*   [x] **Task 0:** Clarify requirements & define scope via Q&A (Completed: 2026-06-14)
*   [x] **Task 1:** Create Product Requirements Document ([PRD.md](file:///home/groot/src/local/learn-quran/PRD.md)) (Completed: 2026-06-14)
*   [x] **Task 2:** Write Technical Specifications ([TechSpec.md](file:///home/groot/src/local/learn-quran/TechSpec.md)) (Completed: 2026-06-14)
*   [x] **Task 3:** Detail User Flows ([AppFlow.md](file:///home/groot/src/local/learn-quran/AppFlow.md)) (Completed: 2026-06-14)
*   [x] **Task 4:** Design Database Schema ([Schema.md](file:///home/groot/src/local/learn-quran/Schema.md)) (Completed: 2026-06-14)
*   [x] **Task 5:** Write Step-by-Step Implementation Roadmap ([ImplementationPlan.md](file:///home/groot/src/local/learn-quran/ImplementationPlan.md)) (Completed: 2026-06-14)
*   [x] **Task 6:** Set Coding Standards & Hard Constraints ([Rules.md](file:///home/groot/src/local/learn-quran/Rules.md)) (Completed: 2026-06-14)
*   [x] **Task 7:** Establish Progress Tracker ([Tracker.md](file:///home/groot/src/local/learn-quran/Tracker.md)) (Completed: 2026-06-14)
*   [x] **Task 8:** Formulate UI/UX Guidelines ([Design.md](file:///home/groot/src/local/learn-quran/Design.md)) (Completed: 2026-06-14)

---

## 2. Milestone Implementation Tracker

### Phase 1: Project Scaffolding
*   [x] **Task 1.1:** Setup Clean Architecture folder layout. (Completed: 2026-06-14)
*   [x] **Task 1.2:** Configure `pubspec.yaml` with Riverpod, Drift, Adhan, and local notification packages. (Completed: 2026-06-14)
*   [x] **Task 1.3:** Setup static analysis and basic code-quality configurations. (Completed: 2026-06-14)

### Phase 2: Drift Local Persistence & Database Seed
*   [x] **Task 2.1:** Implement Drift table schemas. (Completed: 2026-06-14)
*   [x] **Task 2.2:** Run code generator for DB classes. (Completed: 2026-06-14)
*   [x] **Task 2.3:** Prepare pre-seeded SQLite databases and register them as app assets. (Completed: 2026-06-14)
*   [x] **Task 2.4:** Write integration tests for reading and logging. (Completed: 2026-06-14)

### Phase 3: Salat Alarms & Location Computing
*   [x] **Task 3.1:** Implement Adhan calculation repository. (Completed: 2026-06-14)
*   [x] **Task 3.2:** Implement offline local notification scheduler. (Completed: 2026-06-14)
*   [x] **Task 3.3:** Setup daily Salat recalculation worker using Workmanager. (Completed: 2026-06-14)
    Swapped to `android_alarm_manager_plus` on 2026-07-04: `workmanager`
    0.9.0+3 (latest) still applies its own Kotlin Gradle Plugin, which
    Flutter is deprecating in favor of Built-in Kotlin, and there's no
    newer release that fixes it.
    Also on 2026-07-04: the service was implemented but never actually
    invoked anywhere in the app, so this never ran. Bootstrapped it in
    `main()` and added the RECEIVE_BOOT_COMPLETED / SCHEDULE_EXACT_ALARM /
    POST_NOTIFICATIONS manifest permissions it needs. Still missing: a
    runtime permission-request flow for exact alarms (Android 12+) and
    notifications (Android 13+) — until a user grants those manually,
    scheduling can silently no-op.
*   [x] **Task 3.4:** Write prayer calculation tests. (Completed: 2026-06-14)

### Phase 4: Local Embedding & sqlite-vec Integration
*   [x] **Task 4.1:** Setup `sqlite-vec` FFI compilation in Flutter. (Completed: 2026-06-22)
*   [x] **Task 4.2:** Integrate local query embedding model via ONNX. (Completed: 2026-06-22)
*   [x] **Task 4.3:** Setup local RAG Repository for vector queries. (Completed: 2026-06-22)
*   [x] **Task 4.4:** Write vector search tests. (Completed: 2026-06-22)

### Phase 5: On-Device LLM (Gemma 4) Inference Engine
*   [x] **Task 5.1:** Bind `llama.cpp` shared libraries via Dart FFI. (Completed: 2026-06-22)
*   [x] **Task 5.2:** Implement low-end (e2b) vs high-end (e4b) model loader. (Completed: 2026-06-22)
*   [x] **Task 5.3:** Create prompt formatting engines (Sunnah Q&A behavior). (Completed: 2026-06-22)
*   [x] **Task 5.4:** Write model inference test hooks. (Completed: 2026-06-22)

### Phase 6: Core UI Screens
*   [x] **Task 6.1:** Build Dashboard Screen.
*   [x] **Task 6.2:** Build Quran Reader.
*   [x] **Task 6.3:** Build Q&A Agent Chat UI.
*   [x] **Task 6.4:** Build Settings Screen.

### Phase 7: Story Compiler & Engagement Engine
*   [x] **Task 7.1:** Implement `user_engagement_state` tracking. (Completed: 2026-07-04)
*   [x] **Task 7.2:** Implement daily story compiler prompts. Wired into Dashboard Screen. (Completed: 2026-07-04)
*   [x] **Task 7.3:** Write story-caching integration tests. (Completed: 2026-07-04)

### Phase 8: System Verification & Polish
*   [x] **Task 8.1:** Run safety and accuracy sweeps. (Completed: 2026-07-04)
*   [ ] **Task 8.2:** Run performance profiling on low-end test devices.
    BLOCKED (2026-07-04): needs a real GGUF LLM + ONNX embedding model in
    `assets/models/` (currently only `.gitkeep`) and a physical/emulated
    low-end Android device — neither is available in this dev environment.
    Revisit once real model assets are added.
*   [x] **Task 8.3:** Create release builds. (Completed: 2026-07-04)
    Scaffolded the missing `android/` platform project (`flutter create`
    had never been run for a target), installed the Android SDK/NDK
    toolchain, fixed two real build-blocking bugs (`EdgeInsets.bottom`
    isn't a constructor; onnxruntime 1.4.1's stale compileSdk vs. newer
    transitive androidx deps), and wired up release signing.
    `flutter build apk --release` succeeds and produces a verified-signed
    84.8MB APK. Signed with a throwaway dev keystore
    (`android/app/upload-keystore.jks`, gitignored) — swap
    `android/key.properties` and the keystore for real production signing
    credentials before an actual Play Store release. No iOS target was
    scaffolded (no Mac/Xcode available in this environment).
    UPDATE (2026-07-05): iOS was subsequently scaffolded (see Task 9.2) but
    remains unbuildable here — still no Mac/Xcode/CocoaPods available.

### Phase 9: Permissions Onboarding
*   [x] **Task 9.1:** Build one-time permissions onboarding flow (notifications + exact-alarm scheduling) and a Settings fallback status card. (Completed: 2026-07-04)
    See design: [docs/superpowers/specs/2026-07-04-permissions-onboarding-design.md](docs/superpowers/specs/2026-07-04-permissions-onboarding-design.md)
*   [x] **Task 9.2:** Address known-issues cleanup pass. (Completed: 2026-07-05)
    - Fixed all 64 pre-existing `flutter analyze` info-level lints (0
      remaining): quote-style, deprecated `withOpacity`/`activeColor`/
      RadioListTile `groupValue`/`onChanged` APIs, missing `const`,
      unawaited future, `use_super_parameters`, and a documented
      `ignore_for_file` for `llama_ffi.dart`'s intentionally C-mirroring
      typedef names.
    - Revisited three Minor findings accepted-as-is during the Phase 9.1
      review: guarded `PermissionsOnboardingScreen`'s Skip button against
      double-tap, parallelized Settings' permission checks with
      `Future.wait`, and added a `Platform.isAndroid` guard to
      `_AppEntryGate` so non-Android platforms skip onboarding.
    - Scaffolded the `ios/` platform directory (`flutter create
      --platforms=ios`) — best-effort only, still unbuildable without a
      Mac/Xcode/CocoaPods. Real iOS signing credentials and iOS-side
      permission handling remain out of reach in this environment.

### Phase 10: Runtime Model Download
*   [x] **Task 10.1:** Build runtime Gemma 4 model download (Hugging Face, resumable), device-RAM-based recommendation, and Settings UI (download/progress/delete/Wi-Fi-only toggle). (Completed: 2026-07-05)
    See design: [docs/superpowers/specs/2026-07-05-model-download-design.md](docs/superpowers/specs/2026-07-05-model-download-design.md)
    Fixed a real bug found along the way: `LlmService._detectDeviceRamGb()`
    only checked `Platform.isLinux`, so it always fell back to a hardcoded
    4.0GB on real Android devices — the RAM-based recommendation never
    worked before this. Now checks `Platform.isAndroid` too.

### Phase 11: Multi-Platform Configuration
*   [x] **Task 11.1:** Scaffold Linux, Windows, and macOS platform targets (`flutter create --platforms=linux,windows,macos`). (Completed: 2026-07-05)
    Same native FFI/sqlite3 story as Android/iOS (`NativeDatabase`,
    `dart:ffi`) — no database-layer changes needed. Linux desktop toolchain
    (clang, ninja, GTK3 dev headers, GStreamer for `audioplayers_linux`) was
    installed and `flutter build linux --debug` succeeds and runs — the only
    platform besides Android with a genuine, verified build in this
    environment. Windows/macOS remain scaffold-only (no matching build host
    here); same treatment as iOS.
*   [ ] **Task 11.2:** Web platform.
    BLOCKED — not an environment limitation, a real code incompatibility:
    `flutter build web` fails outright (`Error: Only JS interop members may
    be 'external'`) because `onnxruntime`'s and `llama_ffi.dart`'s `dart:ffi`
    bindings, and Drift's `NativeDatabase`, cannot compile to JS at all. This
    app's entire storage/inference stack is FFI-based. Making web work for
    real means separate web implementations for each: Drift's WASM backend,
    a JS-interop embedding runtime, and a browser-capable LLM runtime (e.g.
    wllama/web-llm) in place of llama.cpp — a multi-week architecture
    project, not a config change. Scaffold was generated, verified broken,
    then reverted rather than leaving a platform directory that implies
    false support.
