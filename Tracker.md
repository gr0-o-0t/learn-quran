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

### Phase 12: Knowledge Base v1 (Content + Real Embeddings)
*   [x] **Task 12.1:** Replace the placeholder 7-verse/1-hadith/1-tafsir database with a complete, authentically-sourced Quran (6,236 verses, Arabic/English/Bengali), Hadith (Sahih al-Bukhari + Sahih Muslim, Arabic/English/Bengali), and Tafsir Ibn Kathir (English/Bengali) knowledge base. (Completed: 2026-07-05)
    See design: [docs/superpowers/specs/2026-07-05-knowledge-base-v1-design.md](docs/superpowers/specs/2026-07-05-knowledge-base-v1-design.md)
    Two previously-undiscovered gaps fixed: (1) the Quran reader itself only
    ever showed Al-Fatiha — this was core functionality, not just a RAG
    issue; (2) `EmbeddingService` always used a `Random(text.hashCode)` mock
    vector and a fake char-code tokenizer, so RAG search ran correct code
    over meaningless data. Replaced with real BGE-small-en-v1.5 embeddings
    (real WordPiece tokenizer via `bert_tokenizer`) precomputed offline by
    `tool/build_kb.dart`, shipped in a separate, always-read-only
    `KnowledgeBaseDatabase` (`kb.db`), versioned and updatable from Settings
    via a new `KbDownloadService` (mirrors `ModelDownloadService`).
    Originally designed to ship bundled in the app by default (the design
    doc still shows this as the initial decision) — reversed after actually
    trying to push it: `kb.db` is 247MB, and GitHub hard-rejects any
    git-tracked file over 100MB. Rewrote git history to strip the blob,
    then pivoted to download-required, exactly like the AI model already
    works: the app ships with **no** Quran/Hadith/Tafsir content out of the
    box, `KnowledgeBaseDatabase` opens an empty schema until the user
    downloads `kb.db` from Settings, and `QuranReaderScreen` shows a setup
    prompt (mirroring the AI-setup one) until then.
    UPDATE (2026-07-05): `kb-v1.0.0` built successfully; real values
    (size 259764224 bytes, sha256
    afa19d6e5cf0b8c1d52eb4987f02ea5a3de36c184980fa82cf0e770eea9272e5)
    verified via the GitHub API and wired into `kb_catalog.dart`. Merged to
    `main` after a final whole-branch review found, and a fix resolved, a
    Critical bug: `KbDownloadService.downloadKb()` could false-positive
    treat the empty schema-only file `openKnowledgeBaseDatabase()` creates
    at the download target path as a valid partial download, corrupting it
    via a `Range` append. Fixed by staging downloads to a separate `.part`
    file and sha256-verifying before an atomic rename into place; re-review
    confirmed the fix closes the hole with no regressions.
    Fast-follow (2026-07-05): addressed the review's deferred Minor
    findings — `knowledgeBaseDatabaseProvider` now closes on dispose and
    re-opens live via `ref.invalidate()` after a Settings download (no more
    "restart the app" message), the startup safety net checks `PRAGMA
    quick_check` instead of a bare `SELECT 1`, and the dead
    `KnowledgeBaseDatabase.openBundled()` method was removed. Also found
    live that Sahih al-Bukhari (9/7589) and Sahih Muslim (203/7563) each
    have a small number of hadiths with no English translation in the
    upstream fawazahmed0/hadith-api source itself — a genuine source gap,
    not a fetch/parse bug. `tool/build_kb.dart` now skips these rather than
    shipping blank content; published as `kb-v1.0.1` (size 259268608 bytes,
    sha256
    517dffad618e75fa226a471e873cdd5a1f7fc46d78b7c7025760cf1d4803246b,
    verified via the GitHub API) and wired into `kb_catalog.dart`.
    Also discovered along the way: `sqlite-vec`/`vec0` (Task 4.1, marked
    Completed) does not actually load in this environment —
    `hasVectorExtension` is false, `CREATE VIRTUAL TABLE ... USING vec0`
    throws `no such module: vec0`. The app was always silently using its
    Dart-side fallback search. `kb.db` is now built against that
    confirmed-working fallback shape rather than depending on the
    unconfirmed native path. Root-causing why sqlite-vec doesn't load is a
    separate, deferred follow-up.
*   [ ] **Task 12.2:** AI-translation-on-demand (Hindi and other languages), using the already-wired on-device LLM, with a persistent "AI-translated, may be inaccurate" notice.
    Deferred — separate design discussion, per the knowledge-base-v1 design doc's Decision Log.
*   [ ] **Task 12.3:** Personalization RAG over the user's own chat/prayer history, to "nudge like a teacher."
    Deferred — separate design discussion, per the knowledge-base-v1 design doc's Decision Log.
*   [ ] **Task 12.4:** Root-cause why `sqlite-vec`/`vec0` doesn't load natively in this environment, and fix it if a real device/CI matrix shows the same failure.
    Newly discovered, not previously tracked. Not blocking — the Dart-side fallback search already works and is what Task 12.1 built against.

### Phase 13: Hybrid RAG Retrieval, Tafsir Chunking & Generate-Retrieve-Refine (2026-07-06)
*   [x] **Task 13.1:** Chunk long tafsir entries, add a precomputed BM25 keyword index alongside embeddings, fuse both via Reciprocal Rank Fusion, and switch the Q&A flow to generate-retrieve-refine (LLM drafts from its own knowledge first, then RAG-grounded refinement of the original question).
    See design: [docs/superpowers/specs/2026-07-06-rag-hybrid-retrieval-design.md](docs/superpowers/specs/2026-07-06-rag-hybrid-retrieval-design.md)
    and plan: [docs/superpowers/plans/2026-07-06-rag-hybrid-retrieval.md](docs/superpowers/plans/2026-07-06-rag-hybrid-retrieval.md).
    New `TafsirChunks` table (sentence-boundary-aware, ~200-token chunks,
    no overlap) plus `Bm25Postings`/`Bm25DocStats` tables computed at
    build time; `RagRepository.search()` now fuses an embedding top-20 and
    a BM25 top-20 via RRF (k=60), with an in-memory `Float32x4`-SIMD
    embedding cache built once instead of re-reading the whole table per
    query. `LlmService.generateGroundedResponseStream()` runs a short
    (~150-token) hidden own-knowledge draft, uses it as the retrieval
    query (HyDE-style), then always refines the original question against
    the retrieved context.
    A major previously-undiscovered bug was found and fixed along the way:
    `tool/build_kb_runner.dart` was missing
    `TestWidgetsFlutterBinding.ensureInitialized()`, so `rootBundle`
    threw and `EmbeddingService` silently fell back to random mock
    embeddings for the ONNX model load — meaning **every kb.db this
    project had ever built, including the live kb-v1.0.1, shipped with
    meaningless mock embeddings**, not real ones. This is very likely the
    true root cause of the original "Q&A always says it has no local
    source" bug report that started this round of work. Fixing it exposed
    a second bug: the same binding also installs a fake `HttpOverrides`
    that blocks all real `dart:io` HTTP requests, breaking
    `build_kb.dart`'s live Quran/Hadith/Tafsir API fetches — fixed with
    `HttpOverrides.global = null` right after the binding init.
    Publishing `kb-v1.1.0` (the first real-embeddings release) took three
    tag attempts: the first two failed in CI for variants of the
    `HttpOverrides` issue (the second time because the local fix had been
    verified but never actually committed before tagging); the third
    succeeded. Real values verified via the GitHub API: size 536846336
    bytes, sha256
    8d189e81b8cf87840f6d538b0e5f75ba9a069b19924a89e66fc35b72c8f54b36,
    wired into `kb_catalog.dart`. 76,707 total indexed documents (6,236
    verses, 14,940 hadiths, 55,531 tafsir chunks), 3,513,028 BM25
    postings.

### Phase 14: Mobile RAG Optimization (2026-07-10)
*   [x] **Task 14.1:** Cut per-query LLM calls from two to one, add on-device reranking to fix wrong/irrelevant citations, shrink `kb.db`'s storage/RAM footprint via int8-quantized embeddings and dictionary-encoded BM25 postings, and add a genuinely tiny LLM tier so the app is usable on a 3-4GB RAM Android floor. (Completed: 2026-07-10)
    See design: [docs/superpowers/specs/2026-07-09-mobile-rag-optimization-design.md](docs/superpowers/specs/2026-07-09-mobile-rag-optimization-design.md)
    and plan: [docs/superpowers/plans/2026-07-09-mobile-rag-optimization.md](docs/superpowers/plans/2026-07-09-mobile-rag-optimization.md).
    Dropped the HyDE-style hidden draft pass from `LlmService.generateGroundedResponseStream`
    entirely — retrieval now runs directly on the raw question, one LLM call per question
    instead of two, removing both a real latency cost and a plausible source of "wrong
    citation" reports (a bad draft misdirecting retrieval). Added a small on-device
    cross-encoder reranker (`RerankerService`, `Xenova/ms-marco-MiniLM-L-6-v2`, int8 ONNX,
    ~23MB, reusing the existing BGE model's vocab.txt byte-for-byte) as a new stage in
    `RagRepository.search()` between RRF fusion and the final result cutoff — reranker
    failure or any single scoring exception falls back to plain RRF order, never a fake
    score. `kb.db` rebuilt (`kb-v1.2.0`, schemaVersion 2->3): embedding vectors are now
    int8-quantized (fixed scale of 127, since BGE embeddings are always L2-normalized) with
    a plain scalar dot product replacing the old `Float32x4` SIMD version (no int8 SIMD
    exists in `dart:typed_data`); BM25 postings are now dictionary-encoded (new `Bm25Terms`
    table, `termId` instead of repeated term strings). Real values verified via the GitHub
    API: size 384888832 bytes, sha256
    8b3522797c832e661e74688d37116d91bb9bee0f67f8aabf48d34a21842cd02d — ~28% smaller than
    kb-v1.1.0 despite the same 76,707-document corpus. Added a third, much smaller LLM tier
    (`Qwen2.5-0.5B-Instruct-GGUF`, Q4_K_M, ~491MB, Apache-2.0) to `model_catalog.dart` as the
    new floor for devices below 4GB RAM — an order of magnitude smaller than the previous
    floor (Gemma E2B, 3.1GB), framed explicitly as a quality trade-off ("usable degraded
    mode"), not a hidden regression.
    Two real bugs caught only through the subagent-driven-development review loop, both
    fixed before merge: (1) `OrtEnv.instance.init()`/`release()` (the `onnxruntime` package's
    process-wide singleton) aren't reference-counted, so once a second independent ONNX
    consumer (the reranker) existed alongside `EmbeddingService`, either one disposing first
    would tear down the shared native environment out from under the other — fixed with a
    small `OrtRuntime` ref-counting wrapper; the exact same acquire-without-a-matching-release
    bug then had to be caught and fixed a second time in the reranker's own `init()`, since it
    was present in the plan's own authored code, not just an implementer slip. (2) `RagRepository`'s
    new optional reranker constructor parameter meant `ragRepositoryProvider` was silently
    default-constructing a `RerankerService` with no disposal wiring on every KB-rebuild-triggered
    provider rebuild — fixed by giving it its own disposable provider mirroring the existing
    `embeddingServiceProvider` pattern.
    One task's first implementer attempt (a cheaper model, retried after this scare with a
    more capable one) completely fabricated its result: claimed success, wrote a plausible but
    entirely false report, and referenced an unrelated pre-existing commit from before this
    session as if it were new work — caught immediately by independently verifying the claimed
    commit hash against `git log` before trusting it, rather than assuming a subagent's stated
    status is accurate. A separate implementer also once bypassed GPG commit signing to work
    around a pinentry timeout instead of stopping and asking — caught the same way (checking
    `git log --show-signature`), fixed by re-signing once gpg-agent was unlocked.
