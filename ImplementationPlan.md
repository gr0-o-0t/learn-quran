# Implementation Plan (ImplementationPlan) - Learn Quran Offline Mobile App

This step-by-step road-map is organized into sequential phases, following Clean Architecture and test-driven development (TDD) best practices.

---

## Phase 1: Project Scaffolding & Basic Setup
*   **Task 1.1:** Initialize the Flutter project structure using standard Clean Architecture directory layouts:
    ```
    lib/
    ├── core/           # Common utilities, DI, theme
    ├── data/           # Database, repositories, LLM FFI bindings
    ├── domain/         # Use Cases, Entities, Agent interfaces
    └── presentation/   # ViewModels (Riverpod), Screens, Widgets
    ```
*   **Task 1.2:** Configure `pubspec.yaml` with core dependencies:
    *   State Management: `flutter_riverpod`, `riverpod_annotation`
    *   Database: `drift`, `sqlite3_flutter_libs`
    *   Utilities: `path_provider`, `uuid`, `geolocator`, `adhan`
    *   UI & Media: `google_fonts`, `audioplayers`, `flutter_local_notifications`, `workmanager`
*   **Task 1.3:** Setup basic code-quality tools and linters (e.g. `flutter_lints`).

---

## Phase 2: Drift Local Persistence & Database Seed
*   **Task 2.1:** Implement Drift table schemas matching `Schema.md` definitions.
*   **Task 2.2:** Configure Drift code generator to generate database bindings and migrations.
*   **Task 2.3:** Prepare pre-seeded SQLite database assets (Quran translations, authentic Hadith, and Tafsir index files).
*   **Task 2.4:** Write integration tests verifying read-only access to translations and write capabilities for user logs.

---

## Phase 3: Salat Alarms & Location Computing
*   **Task 3.1:** Implement a repository layer wrapping `adhan` to calculate daily Salat times using local GPS coordinates or manual overrides.
*   **Task 3.2:** Implement alarm scheduler wrapper using `flutter_local_notifications` for offline triggers.
*   **Task 3.3:** Configure background worker (`workmanager`) to run every 24 hours to refresh prayer notifications and avoid scheduling drift.
*   **Task 3.4:** Create unit tests verifying prayer calculation accuracy across different time zones.

---

## Phase 4: Local Embedding & sqlite-vec Integration
*   **Task 4.1:** Integrate `sqlite-vec` binary dependency via FFI in Flutter to support SQLite virtual vector tables.
*   **Task 4.2:** Integrate a lightweight multilingual embedding model (e.g. via `onnxruntime_flutter`) to run local query vectorization.
*   **Task 4.3:** Set up the RAG Repository to query similarity metrics on `vec_knowledge_base` using cosine similarity.
*   **Task 4.4:** Write integration tests proving that queries return relevant Quran verses and Hadiths correctly.

---

## Phase 5: On-Device LLM (Gemma 4) Inference Engine
*   **Task 5.1:** Set up native FFI bindings to load `llama.cpp` shared libraries on iOS and Android.
*   **Task 5.2:** Implement the model loader logic that checks system memory profile and loads the appropriate model (Gemma 4 e2b for lower-end, Gemma 4 e4b for higher-end devices).
*   **Task 5.3:** Create prompt formatting engines mapping user inputs, retrieved context, and the Sunnah-inspired behavior instructions (calm, gentle, anti-fabrication).
*   **Task 5.4:** Write FFI unit tests loading a dummy quantized model to verify token-streaming callbacks.

---

## Phase 6: Core UI Screens
*   **Task 6.1:** Build Dashboard Screen displaying Salat timers, completed checkboxes, and a reflection card.
*   **Task 6.2:** Build Quran Reader with lazy-loading list, translation selectors, word-by-word popovers, and Tafsir bottom drawer.
*   **Task 6.3:** Build Q&A Agent chat interface supporting streaming replies, source citation widgets, and chat history lists.
*   **Task 6.4:** Build Settings Screen supporting manual coordinates, LLM profiles selector, and privacy reset options.

---

## Phase 7: Story Compiler & Engagement Engine
*   **Task 7.1:** Implement local metric logging (read history, search tags, prayer logs) compiling into `user_engagement_state`.
*   **Task 7.2:** Implement the offline daily reflection compiler: triggers a specific background LLM prompt combining user metrics to output a moral reflection or Quranic story.
*   **Task 7.3:** Build unit tests checking the robustness of engagement logging and daily story updates.

---

## Phase 8: System Verification & Polish
*   **Task 8.1:** Run automated compliance sweeps checking that LLM outputs reject out-of-scope theology questions and never fabricate answers.
*   **Task 8.2:** Performance-profile LLM RAM usage and execution latency on lower-end devices.
*   **Task 8.3:** Finalize release builds and verification.
