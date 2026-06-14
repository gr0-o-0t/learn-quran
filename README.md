# Learn Quran Offline Mobile App

An offline-first cross-platform mobile application built with **Flutter (Dart)** designed to help people learn and understand the Holy Quran in their native languages. 

Rather than focusing solely on rote memorization, this app focuses on deep understanding and provides a respectful, calm, and gentle Q&A experience modeled after the Sunnah of Prophet Muhammad (SAW). It executes all LLM inference and RAG indexing completely offline on the user's device for absolute privacy and resilience.

---

## 📖 Planning & Memory Architecture
This project is configured for **AI-Assisted Development** using the `not-a-vibe-coder` planning standard. The following 8 planning files serve as the persistent memory of this codebase:

1.  **[PRD.md](file:///home/groot/src/local/learn-quran/PRD.md):** Target requirements, vision, user experience, and model scopes.
2.  **[TechSpec.md](file:///home/groot/src/local/learn-quran/TechSpec.md):** Architecture details, Riverpod state management, Drift DB, FFI, local LLM, and offline RAG.
3.  **[AppFlow.md](file:///home/groot/src/local/learn-quran/AppFlow.md):** Detailed navigation maps, onboarding flows, and screen descriptions.
4.  **[Schema.md](file:///home/groot/src/local/learn-quran/Schema.md):** Drift/SQLite relational schemas and `sqlite-vec` virtual tables.
5.  **[ImplementationPlan.md](file:///home/groot/src/local/learn-quran/ImplementationPlan.md):** Step-by-step 8-phase implementation roadmap.
6.  **[Rules.md](file:///home/groot/src/local/learn-quran/Rules.md):** Technical rules, theological safety constraints, and code standards.
7.  **[Tracker.md](file:///home/groot/src/local/learn-quran/Tracker.md):** Living progress tracker showing completed tasks.
8.  **[Design.md](file:///home/groot/src/local/learn-quran/Design.md):** Visual system, color tokens, typography (Amiri & Inter), and micro-animations.

---

## 🛠️ AI-Assisted Development & Skills Setup
This repository is pre-configured to be developed collaboratively with agentic AI assistants. It integrates the following skill bundles from the `antigravity-awesome-skills` repository:

*   **Essentials:** Core agent workflows, TDD cycles, and planning templates.
*   **Agent Architect & LLM Application Developer:** Local FFI bindings configuration, prompt engineering, and offline RAG setup.
*   **Data Engineering:** Offline SQLite schemas, virtual tables, and Drift migrations.
*   **Mobile Developer:** Flutter Clean Architecture patterns, layout spacing rules, and reactive state management.
*   **Security Developer:** Local sandbox data hygiene, location computation privacy, and log security.
*   **Skill Author & OSS Maintainer:** Structured git commits, PR summaries, and custom skill generation.

---

## 🚀 Running the Project Locally

### 1. Install Flutter SDK
Make sure you have Flutter SDK installed on your system. If not, follow the official instructions at [flutter.dev](https://flutter.dev/docs/get-started/install).

### 2. Fetch Dependencies
Fetch the required Dart packages:
```bash
flutter pub get
```

### 3. Generate Database Code
The app uses **Drift** for local database management. Generate the necessary generated classes (e.g. `app_database.g.dart`):
```bash
dart run build_runner build --delete-conflicting-outputs
```

### 4. Run the App
Launch on a simulator/emulator or connected physical device:
```bash
flutter run
```
