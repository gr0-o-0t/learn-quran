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
*   [ ] **Task 7.3:** Write story-caching integration tests.

### Phase 8: System Verification & Polish
*   [ ] **Task 8.1:** Run safety and accuracy sweeps.
*   [ ] **Task 8.2:** Run performance profiling on low-end test devices.
*   [ ] **Task 8.3:** Create release builds.
