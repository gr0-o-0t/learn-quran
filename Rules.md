# Coding Standards & Project Rules (Rules) - Learn Quran Offline Mobile App

These rules represent hard constraints that must be followed by all developers and AI agents working on this codebase.

---

## 1. Theological & AI Generation Rules (Strict)
*   **Sunnah Teaching Methodology:** Prompt templates and system prompts must ensure the agent responds gently, respectfully, and clearly. Never use condescending, harsh, or overly clinical language.
*   **Zero-Hallucination Policy:** If the local RAG database does not contain verification for a query, the model MUST politely state that it does not have enough information to answer, citing its source boundaries, rather than attempting to guess.
*   **Citations Required:** Every AI statement explaining a Quranic concept or a Hadith must contain a citation reference linking to a valid `surah_number:ayah_number` or a Hadith index from the SQLite database.

---

## 2. Technical & Offline-First Constraints
*   **No Unapproved Networks:** Core packages must not make any external network requests. All dependencies (models, translations, databases) must reside locally in assets or application sandboxes.
*   **Flutter Architecture:**
    *   Follow **Clean Architecture**: Never mix UI logic with data manipulation or FFI invocation.
    *   Keep business logic completely decoupled from view representations.
*   **State Management:**
    *   Use **Riverpod** for state management and dependency injection.
    *   Do not use raw stateful widgets for managing cross-screen state. Use `NotifierProvider` or `StateNotifierProvider`.
*   **TDD Workflow:**
    *   Write unit tests for new services, calculation managers (Adhan calculation offsets), and repository methods BEFORE implementing the actual code.
    *   Ensure all tests pass before checking off items in `Tracker.md`.

---

## 3. SQLite & Drift Database Rules
*   **Pre-compiled Index:** Never run text-embedding indexing on-device for the main Quran and Hadith database. Always use the pre-seeded SQLite databases and vector store shipped as assets.
*   **Migrations:** Always use Drift's schema generator and migration testing framework when modifying tables to avoid corruption of user data on upgrades.
*   **Thread Safety:** Access the database through a singleton instance managed by a Riverpod provider to prevent concurrent write locks.

---

## 4. Code Quality & Pre-Commit Checks
*   **Formatting:** Run `dart format .` to format the codebase before every commit.
*   **Lints:** Maintain zero errors and warnings from `flutter analyze`. If a warning cannot be avoided, add a specific, documented ignore comment with justifications.
*   **File Naming:** Use `snake_case` for all files, directories, and assets. Use `CamelCase` for classes and `camelCase` for variables/methods.
