# RAG Hybrid Retrieval, Tafsir Chunking & Generate-Retrieve-Refine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix silent tafsir truncation, replace brute-force per-query retrieval with a fast in-memory hybrid (embedding + BM25) search, and switch the Q&A screen from retrieve-then-generate to a hidden draft-then-retrieve-then-refine flow.

**Architecture:** `tool/build_kb.dart` chunks long tafsir entries and precomputes a BM25 index into new `kb.db` tables. `RagRepository` caches all embeddings in memory (SIMD dot products) and fuses embedding + BM25 rankings via Reciprocal Rank Fusion. `LlmService` gains a `generateGroundedResponseStream` method that drafts a short hypothetical answer (HyDE), retrieves using that draft, then reuses the existing single-pass `generateResponseStream` as its "refine" step.

**Tech Stack:** Dart/Flutter, Drift (SQLite ORM), `dart:typed_data` (`Float32x4` SIMD), no new package dependencies.

**Full design reference:** `docs/superpowers/specs/2026-07-06-rag-hybrid-retrieval-design.md` — read it if anything here is ambiguous; this plan implements that design exactly.

## Global Constraints

- Fully offline: no new network calls anywhere in this feature. BM25 and chunking are pure Dart — no new package dependencies, no new on-device ML model.
- `sqlite-vec`/`vec0` is NOT being retried this round — retrieval speed work targets the pure-Dart path only.
- Requires a new KB version, `kb-v1.1.0` (schema change: new tables). The existing `tafsirs` table's shape and content are unchanged — it's still read by `QuranRepository.getTafsirForVerse()` for full-content display and must never be chunked.
- Final fused retrieval result count is 5 (up from today's 3). Each of the two retrieval methods (embedding, BM25) contributes its own top-20 before fusion.
- Reciprocal Rank Fusion constant `k = 60`.
- Tafsir chunking: sentence-grouped, target ~200 tokens/chunk (measured by the real tokenizer, not word count), no overlap. A single sentence exceeding the budget becomes its own over-budget chunk rather than being split mid-sentence.
- The draft pass is capped at 150 tokens, is never shown to the user, and is never used as a fallback answer — if retrieval (even hybrid) finds nothing relevant, the refine pass still carries the existing decline-if-insufficient instruction.
- The mock/no-engine path in `LlmService` (`_generateMockResponse`) must remain behaviorally unchanged — `test/core/services/llm_compliance_test.dart` and the existing `generateResponseStream` tests in `test/core/services/llm_service_test.dart` must keep passing without modification.
- `daily_story_service.dart`'s use of `LlmService.generateResponseStream` (no RAG, empty context) is out of scope and must be unaffected.
- BM25 lookups against an older kb.db missing the new tables must degrade to "no keyword matches" rather than throwing.

---

### Task 1: RAG text-processing utilities (chunking + BM25 tokenizer)

**Files:**
- Create: `lib/core/utils/text_chunking.dart`
- Create: `lib/core/utils/bm25_tokenizer.dart`
- Test: `test/core/utils/text_chunking_test.dart`
- Test: `test/core/utils/bm25_tokenizer_test.dart`

**Interfaces:**
- Produces: `List<String> chunkText(String text, {required int maxTokens, required int Function(String) countTokens})` — used by Task 5 (`tool/build_kb.dart`).
- Produces: `List<String> tokenizeForBm25(String text)` — used by Task 3 (`Bm25Index`) and Task 5 (`tool/build_kb.dart`). Both call sites MUST use this exact function so index-time and query-time tokenization never drift apart.

- [ ] **Step 1: Write the failing test for `chunkText`**

Create `test/core/utils/text_chunking_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/utils/text_chunking.dart';

int _wordCount(String s) => s.trim().split(RegExp(r'\s+')).length;

void main() {
  group('chunkText', () {
    test('returns the whole text as one chunk when it already fits', () {
      final result = chunkText('Short text here.', maxTokens: 10, countTokens: _wordCount);
      expect(result, ['Short text here.']);
    });

    test('returns an empty list for empty/blank input', () {
      expect(chunkText('', maxTokens: 10, countTokens: _wordCount), isEmpty);
      expect(chunkText('   ', maxTokens: 10, countTokens: _wordCount), isEmpty);
    });

    test('groups sentences into chunks without exceeding the token budget', () {
      // Each sentence is 3 words; a budget of 5 tokens fits at most one
      // sentence per chunk (adding a 2nd would be 6 tokens).
      const text = 'One two three. Four five six. Seven eight nine.';
      final result = chunkText(text, maxTokens: 5, countTokens: _wordCount);
      expect(result, [
        'One two three.',
        'Four five six.',
        'Seven eight nine.',
      ]);
    });

    test('groups multiple short sentences into one chunk when they fit together', () {
      const text = 'One two. Three four. Five six.';
      // Each sentence is 2 words; a budget of 4 tokens fits two sentences.
      final result = chunkText(text, maxTokens: 4, countTokens: _wordCount);
      expect(result, [
        'One two. Three four.',
        'Five six.',
      ]);
    });

    test('never splits mid-sentence, even if a single sentence exceeds the budget', () {
      const text = 'One two three four five. Six seven.';
      final result = chunkText(text, maxTokens: 3, countTokens: _wordCount);
      expect(result, [
        'One two three four five.', // over budget but kept whole
        'Six seven.',
      ]);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/utils/text_chunking_test.dart`
Expected: FAIL — `Error: Error when reading 'lib/core/utils/text_chunking.dart': No such file or directory`

- [ ] **Step 3: Write `chunkText`**

Create `lib/core/utils/text_chunking.dart`:

```dart
final _sentenceBoundary = RegExp(r'(?<=[.!?])\s+');

/// Splits [text] into chunks of roughly [maxTokens] tokens (measured by
/// [countTokens]), grouping whole sentences greedily and never splitting
/// mid-sentence. A single sentence that alone exceeds [maxTokens] becomes
/// its own (over-budget) chunk rather than being cut apart.
///
/// Returns a single-element list containing all of [text] unchanged if it
/// already fits within [maxTokens] — the common case for short entries.
/// Returns an empty list for empty/blank input.
List<String> chunkText(
  String text, {
  required int maxTokens,
  required int Function(String) countTokens,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  if (countTokens(trimmed) <= maxTokens) return [trimmed];

  final sentences = trimmed.split(_sentenceBoundary).where((s) => s.trim().isNotEmpty).toList();
  final chunks = <String>[];
  final currentSentences = <String>[];
  var currentTokens = 0;

  for (final sentence in sentences) {
    final sentenceTokens = countTokens(sentence);
    if (currentSentences.isNotEmpty && currentTokens + sentenceTokens > maxTokens) {
      chunks.add(currentSentences.join(' '));
      currentSentences.clear();
      currentTokens = 0;
    }
    currentSentences.add(sentence);
    currentTokens += sentenceTokens;
  }
  if (currentSentences.isNotEmpty) {
    chunks.add(currentSentences.join(' '));
  }
  return chunks;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/utils/text_chunking_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Write the failing test for `tokenizeForBm25`**

Create `test/core/utils/bm25_tokenizer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/utils/bm25_tokenizer.dart';

void main() {
  group('tokenizeForBm25', () {
    test('lowercases and splits on non-word characters', () {
      expect(tokenizeForBm25('Patience, Sabr! And Prayer.'), ['patience', 'sabr', 'prayer']);
    });

    test('drops common stopwords', () {
      expect(tokenizeForBm25('the patience of the prophet'), ['patience', 'prophet']);
    });

    test('drops single-character tokens', () {
      expect(tokenizeForBm25('a b patience c'), ['patience']);
    });

    test('returns an empty list for text with no indexable terms', () {
      expect(tokenizeForBm25('the a an'), isEmpty);
    });
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/core/utils/bm25_tokenizer_test.dart`
Expected: FAIL — `Error: Error when reading 'lib/core/utils/bm25_tokenizer.dart': No such file or directory`

- [ ] **Step 7: Write `tokenizeForBm25`**

Create `lib/core/utils/bm25_tokenizer.dart`:

```dart
/// A tiny, deliberately simple tokenizer shared by tool/build_kb.dart (index
/// time) and Bm25Index (query time) — both MUST use the exact same rules,
/// or BM25 term lookups silently stop matching.
final _wordPattern = RegExp(r"[a-z0-9']+");

const _stopwords = {
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'for', 'from', 'has',
  'he', 'in', 'is', 'it', 'its', 'of', 'on', 'that', 'the', 'to', 'was',
  'were', 'will', 'with',
};

/// Lowercases [text], splits into word tokens, and drops single-character
/// tokens and common English stopwords.
List<String> tokenizeForBm25(String text) {
  return _wordPattern
      .allMatches(text.toLowerCase())
      .map((m) => m.group(0)!)
      .where((word) => word.length > 1 && !_stopwords.contains(word))
      .toList();
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/core/utils/bm25_tokenizer_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 9: Commit**

```bash
git add lib/core/utils/text_chunking.dart lib/core/utils/bm25_tokenizer.dart test/core/utils/text_chunking_test.dart test/core/utils/bm25_tokenizer_test.dart
git commit -m "feat: add text chunking and BM25 tokenizer utilities"
```

---

### Task 2: Knowledge base schema — tafsir chunks + BM25 tables

**Files:**
- Modify: `lib/data/local/db/knowledge_base_database.dart`
- Test: `test/data/local/db/knowledge_base_database_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: Drift tables `TafsirChunks`, `Bm25Postings`, `Bm25DocStats` (and their generated `...Companion.insert(...)` constructors, generated by `build_runner`) — used by Task 3 (`Bm25Index`), Task 4 (`RagRepository`), and Task 5 (`tool/build_kb.dart`).
- `TafsirChunks` columns: `id, tafsirId, surahNumber, ayahNumber, author, chunkIndex, contentEnglish`.
- `Bm25Postings` columns: `term, docId, termFrequency`.
- `Bm25DocStats` columns: `docId` (primary key), `docLength`.
- `KnowledgeBaseDatabase.schemaVersion` becomes `2`.

- [ ] **Step 1: Add the new table classes and register them**

Modify `lib/data/local/db/knowledge_base_database.dart` — add these three classes after `class KbMeta` (before the `@DriftDatabase` annotation):

```dart
class TafsirChunks extends Table {
  IntColumn get id => integer()();
  IntColumn get tafsirId => integer()();
  IntColumn get surahNumber => integer()();
  IntColumn get ayahNumber => integer()();
  TextColumn get author => text()();
  IntColumn get chunkIndex => integer()();
  TextColumn get contentEnglish => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Bm25Postings extends Table {
  TextColumn get term => text()();
  IntColumn get docId => integer()();
  IntColumn get termFrequency => integer()();
}

class Bm25DocStats extends Table {
  IntColumn get docId => integer()();
  IntColumn get docLength => integer()();

  @override
  Set<Column> get primaryKey => {docId};
}
```

Then update the `@DriftDatabase` annotation and bump `schemaVersion`:

```dart
@DriftDatabase(tables: [Verses, Hadiths, Tafsirs, KbMeta, TafsirChunks, Bm25Postings, Bm25DocStats])
class KnowledgeBaseDatabase extends _$KnowledgeBaseDatabase {
  KnowledgeBaseDatabase.forTesting(super.executor);

  /// Opens (or creates) the database at an explicit file [path] — used both
  /// by the app (a writable copy of the bundled/downloaded asset) and by
  /// `tool/build_kb.dart` (building a fresh file from scratch).
  KnowledgeBaseDatabase.fromFile(String path) : super(NativeDatabase.createInBackground(File(path)));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createVectorTable();
          await _createBm25TermIndex();
        },
        beforeOpen: (details) async {
          await _createVectorTable();
          await _createBm25TermIndex();
        },
      );

  Future<void> _createVectorTable() async {
    // Always the plain fallback shape — see Rules.md / design doc: the
    // sqlite-vec native extension does not currently load in this
    // environment, so this ships in the format the Dart-side fallback
    // search (RagRepository.search) actually reads.
    await customStatement('''
      CREATE TABLE IF NOT EXISTS vec_knowledge_base (
        rowid INTEGER PRIMARY KEY,
        embedding BLOB
      );
    ''');
  }

  Future<void> _createBm25TermIndex() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_bm25_postings_term ON bm25_postings (term);',
    );
  }
}
```

No in-place data migration is needed: `kb.db` is always either freshly created (empty, via `onCreate`) or a wholesale, hash-verified download at one pinned version (see `kb_download_service.dart`) — never altered incrementally.

- [ ] **Step 2: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: generates the new `...Companion` classes and table getters in `lib/data/local/db/knowledge_base_database.g.dart` with no errors. This file is gitignored — do not `git add` it.

- [ ] **Step 3: Write the failing test**

Modify `test/data/local/db/knowledge_base_database_test.dart` — add a new test inside `void main()`, after the existing two tests:

```dart
  test('creates tafsir_chunks/bm25_postings/bm25_doc_stats tables', () async {
    await db.into(db.tafsirChunks).insert(TafsirChunksCompanion.insert(
          id: const Value(1),
          tafsirId: 1,
          surahNumber: 1,
          ayahNumber: 1,
          author: 'Ibn Kathir',
          chunkIndex: 0,
          contentEnglish: 'First chunk of commentary.',
        ));
    final chunk = await (db.select(db.tafsirChunks)..where((t) => t.id.equals(1))).getSingle();
    expect(chunk.contentEnglish, 'First chunk of commentary.');

    await db.into(db.bm25Postings).insert(
          Bm25PostingsCompanion.insert(term: 'patience', docId: 1, termFrequency: 2),
        );
    final posting = await (db.select(db.bm25Postings)..where((t) => t.term.equals('patience'))).getSingle();
    expect(posting.docId, 1);
    expect(posting.termFrequency, 2);

    await db.into(db.bm25DocStats).insert(
          Bm25DocStatsCompanion.insert(docId: 1, docLength: 42),
        );
    final stats = await (db.select(db.bm25DocStats)..where((t) => t.docId.equals(1))).getSingle();
    expect(stats.docLength, 42);
  });
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/local/db/knowledge_base_database_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/data/local/db/knowledge_base_database.dart test/data/local/db/knowledge_base_database_test.dart
git commit -m "feat(kb): add tafsir_chunks and BM25 tables to the knowledge base schema"
```

---

### Task 3: `Bm25Index` — query-time BM25 keyword search

**Files:**
- Create: `lib/core/services/bm25_index.dart`
- Test: `test/core/services/bm25_index_test.dart`

**Interfaces:**
- Consumes: `tokenizeForBm25` (Task 1); `KnowledgeBaseDatabase`, `Bm25Postings`, `Bm25DocStats`, `KbMeta` (Task 2).
- Produces: `class Bm25Index { Bm25Index(KnowledgeBaseDatabase db); Future<List<MapEntry<int, double>>> search(String query, {int limit = 20}); }` — used by Task 4 (`RagRepository`).

- [ ] **Step 1: Write the failing test**

Create `test/core/services/bm25_index_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/services/bm25_index.dart';
import 'package:learn_quran/data/local/db/knowledge_base_database.dart';

void main() {
  late KnowledgeBaseDatabase db;
  late Bm25Index index;

  setUp(() async {
    db = KnowledgeBaseDatabase.forTesting(NativeDatabase.memory());
    index = Bm25Index(db);

    // 3 tiny documents, each 3 tokens long (so length-normalization is a
    // no-op and results are hand-verifiable from tf/idf alone):
    //   doc 1: "patience patience prophet"
    //   doc 2: "prophet prophet prophet"
    //   doc 3: "prayer prayer prayer"
    await db.batch((batch) {
      batch.insertAll(db.bm25Postings, [
        Bm25PostingsCompanion.insert(term: 'patience', docId: 1, termFrequency: 2),
        Bm25PostingsCompanion.insert(term: 'prophet', docId: 1, termFrequency: 1),
        Bm25PostingsCompanion.insert(term: 'prophet', docId: 2, termFrequency: 3),
        Bm25PostingsCompanion.insert(term: 'prayer', docId: 3, termFrequency: 3),
      ]);
      batch.insertAll(db.bm25DocStats, [
        Bm25DocStatsCompanion.insert(docId: 1, docLength: 3),
        Bm25DocStatsCompanion.insert(docId: 2, docLength: 3),
        Bm25DocStatsCompanion.insert(docId: 3, docLength: 3),
      ]);
      batch.insertAll(db.kbMeta, [
        KbMetaCompanion.insert(key: 'bm25_doc_count', value: '3'),
        KbMetaCompanion.insert(key: 'bm25_avg_doc_length', value: '3.0'),
      ]);
    });
  });

  tearDown(() async {
    await db.close();
  });

  group('Bm25Index', () {
    test('finds the only document containing a rare term', () async {
      final results = await index.search('patience');
      expect(results.map((e) => e.key).toList(), [1]);
    });

    test('ranks a document with higher term frequency above one with lower', () async {
      final results = await index.search('prophet');
      expect(results.map((e) => e.key).toList(), [2, 1]);
    });

    test('returns an empty list for a term not in the index', () async {
      final results = await index.search('nonexistent');
      expect(results, isEmpty);
    });

    test('returns an empty list when BM25 metadata has not been populated', () async {
      final freshDb = KnowledgeBaseDatabase.forTesting(NativeDatabase.memory());
      final freshIndex = Bm25Index(freshDb);
      final results = await freshIndex.search('patience');
      expect(results, isEmpty);
      await freshDb.close();
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/services/bm25_index_test.dart`
Expected: FAIL — `Error: Error when reading 'lib/core/services/bm25_index.dart': No such file or directory`

- [ ] **Step 3: Write `Bm25Index`**

Create `lib/core/services/bm25_index.dart`:

```dart
import 'dart:math';
import 'package:drift/drift.dart';
import '../../data/local/db/knowledge_base_database.dart';
import '../utils/bm25_tokenizer.dart';

const _k1 = 1.2;
const _b = 0.75;

/// Ranks documents by BM25 lexical relevance against a query, using the
/// term-frequency/document-length statistics tool/build_kb.dart precomputes
/// into `Bm25Postings`/`Bm25DocStats`/`KbMeta` at build time.
class Bm25Index {
  final KnowledgeBaseDatabase _db;
  const Bm25Index(this._db);

  /// Returns up to [limit] (docId, score) pairs, highest score first.
  /// Returns an empty list — never throws — if the query has no indexable
  /// terms, if BM25 metadata hasn't been populated (a fresh/empty KB), or if
  /// the KB predates the BM25 tables entirely (an older kb.db) — callers
  /// should treat all of these exactly like "no keyword matches" rather
  /// than a hard failure.
  Future<List<MapEntry<int, double>>> search(String query, {int limit = 20}) async {
    final terms = tokenizeForBm25(query).toSet();
    if (terms.isEmpty) return const [];

    try {
      final docCountRow =
          await (_db.select(_db.kbMeta)..where((t) => t.key.equals('bm25_doc_count'))).getSingleOrNull();
      final avgLengthRow =
          await (_db.select(_db.kbMeta)..where((t) => t.key.equals('bm25_avg_doc_length'))).getSingleOrNull();
      if (docCountRow == null || avgLengthRow == null) return const [];
      final docCount = int.parse(docCountRow.value);
      final avgDocLength = double.parse(avgLengthRow.value);
      if (docCount == 0 || avgDocLength == 0) return const [];

      final scores = <int, double>{};
      for (final term in terms) {
        final postings = await (_db.select(_db.bm25Postings)..where((t) => t.term.equals(term))).get();
        if (postings.isEmpty) continue;

        final df = postings.length;
        final idf = log((docCount - df + 0.5) / (df + 0.5) + 1);

        final docIds = postings.map((p) => p.docId).toList();
        final statsRows = await (_db.select(_db.bm25DocStats)..where((t) => t.docId.isIn(docIds))).get();
        final lengthByDocId = {for (final row in statsRows) row.docId: row.docLength};

        for (final posting in postings) {
          final docLength = lengthByDocId[posting.docId] ?? avgDocLength.round();
          final tf = posting.termFrequency;
          final denom = tf + _k1 * (1 - _b + _b * docLength / avgDocLength);
          scores[posting.docId] = (scores[posting.docId] ?? 0) + idf * (tf * (_k1 + 1)) / denom;
        }
      }

      final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return sorted.take(limit).toList();
    } catch (_) {
      return const [];
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/services/bm25_index_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/bm25_index.dart test/core/services/bm25_index_test.dart
git commit -m "feat: add Bm25Index for query-time keyword search"
```

---

### Task 4: `RagRepository` — in-memory embedding cache, SIMD search, RRF fusion, shared citations

**Files:**
- Modify: `lib/data/repositories/rag_repository.dart`
- Test: `test/data/repositories/rag_repository_test.dart`

**Interfaces:**
- Consumes: `Bm25Index` (Task 3); `TafsirChunks` table (Task 2).
- Produces: `RagRepository.search(String query, {int limit = 5})` (signature unchanged); `RagCitation citationFor(RagSearchResult)` — used by Task 6 (`LlmService`) and Task 7 (`qa_agent_screen.dart`). `RagSearchResult.tafsir` is now typed `TafsirChunk?` (was `Tafsir?`).

- [ ] **Step 1: Write the failing tests**

Replace the entire contents of `test/data/repositories/rag_repository_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:learn_quran/data/local/db/knowledge_base_database.dart';
import 'package:learn_quran/data/repositories/rag_repository.dart';
import 'package:learn_quran/core/services/embedding_service.dart';

/// Mirrors what the offline `tool/build_kb.dart` writes into
/// `vec_knowledge_base` at build time — embeddings are never generated
/// on-device anymore (see RagRepository.search).
Future<void> _insertVector(KnowledgeBaseDatabase db, int rowid, List<double> embedding) async {
  final float32list = Float32List.fromList(embedding);
  final blob = float32list.buffer.asUint8List();
  await db.customStatement(
    'INSERT OR REPLACE INTO vec_knowledge_base(rowid, embedding) VALUES (?, ?)',
    [rowid, blob],
  );
}

void main() {
  late KnowledgeBaseDatabase db;
  late EmbeddingService embeddingService;
  late RagRepository repository;

  setUp(() async {
    db = KnowledgeBaseDatabase.forTesting(NativeDatabase.memory());
    embeddingService = EmbeddingService(forceMock: true);
    repository = RagRepository(db, embeddingService);

    await db.into(db.verses).insert(VersesCompanion.insert(
          id: const drift.Value(1),
          surahNumber: 1,
          ayahNumber: 1,
          juzNumber: 1,
          arabicText: 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
          englishText: 'In the name of Allah, the Entirely Merciful, the Especially Merciful.',
          banglaText: 'পরম করুণাময় অসীম দয়ালু আল্লাহর নামে শুরু করছি।',
        ));

    await db.into(db.hadiths).insert(HadithsCompanion.insert(
          id: const drift.Value(1),
          bookName: 'Sahih al-Bukhari',
          hadithNumber: '1',
          chapterTitle: 'Revelation',
          arabicText: 'إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ',
          englishText: 'Actions are but by intention...',
          banglaText: 'কাজ নিয়তের ওপর নির্ভরশীল...',
        ));

    await db.into(db.tafsirChunks).insert(TafsirChunksCompanion.insert(
          id: const drift.Value(1),
          tafsirId: 1,
          surahNumber: 1,
          ayahNumber: 1,
          author: 'Ibn Kathir',
          chunkIndex: 0,
          contentEnglish: 'Tafsir explaining the meaning of Basmalah.',
        ));

    await _insertVector(
      db,
      1,
      await embeddingService.getEmbedding('In the name of Allah, the Entirely Merciful, the Especially Merciful.'),
    );
    await _insertVector(
      db,
      RagRepository.hadithOffset + 1,
      await embeddingService.getEmbedding('Actions are but by intention...'),
    );
    await _insertVector(
      db,
      RagRepository.tafsirOffset + 1,
      await embeddingService.getEmbedding('Tafsir explaining the meaning of Basmalah.'),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('RagRepository hybrid search', () {
    test('search returns matching segments ordered by similarity', () async {
      final results = await repository.search('name of Allah', limit: 2);

      expect(results, isNotEmpty);
      expect(results.length, lessThanOrEqualTo(2));

      for (final match in results) {
        if (match.type == RagSourceType.verse) {
          expect(match.verse, isNotNull);
          expect(match.verse!.englishText, contains('Allah'));
        } else if (match.type == RagSourceType.hadith) {
          expect(match.hadith, isNotNull);
          expect(match.hadith!.englishText, contains('intention'));
        } else if (match.type == RagSourceType.tafsir) {
          expect(match.tafsir, isNotNull);
          expect(match.tafsir!.contentEnglish, contains('Basmalah'));
        }
      }
    });

    test('a document found only via BM25 ranks first for an exact keyword match', () async {
      // Its mock embedding has no special relationship to the query below —
      // only the exact keyword match should be able to surface it reliably.
      await db.into(db.hadiths).insert(HadithsCompanion.insert(
            id: const drift.Value(2),
            bookName: 'Sahih Muslim',
            hadithNumber: '99',
            chapterTitle: 'Zakat',
            arabicText: 'زَكَاة',
            englishText: 'A rare distinctive keyword: xenocryst appears here.',
            banglaText: 'যাকাত',
          ));
      await _insertVector(
        db,
        RagRepository.hadithOffset + 2,
        await embeddingService.getEmbedding('A rare distinctive keyword: xenocryst appears here.'),
      );
      await db.batch((batch) {
        batch.insertAll(db.bm25Postings, [
          Bm25PostingsCompanion.insert(term: 'xenocryst', docId: RagRepository.hadithOffset + 2, termFrequency: 1),
        ]);
        batch.insertAll(db.bm25DocStats, [
          Bm25DocStatsCompanion.insert(docId: RagRepository.hadithOffset + 2, docLength: 6),
        ]);
        batch.insertAll(db.kbMeta, [
          KbMetaCompanion.insert(key: 'bm25_doc_count', value: '4'),
          KbMetaCompanion.insert(key: 'bm25_avg_doc_length', value: '6.0'),
        ]);
      });

      final results = await repository.search('xenocryst', limit: 1);

      expect(results, hasLength(1));
      expect(results.first.hadith?.id, 2);
    });
  });

  group('citationFor', () {
    test('formats a verse citation with the real surah name', () {
      final result = RagSearchResult(
        type: RagSourceType.verse,
        score: 1,
        verse: Verse(
          id: 1,
          surahNumber: 2,
          ayahNumber: 153,
          juzNumber: 2,
          arabicText: 'عربي',
          englishText: 'Seek help through patience.',
          banglaText: 'বাংলা',
        ),
      );
      final citation = citationFor(result);
      expect(citation.title, 'Surah Al-Baqarah 2:153');
      expect(citation.text, 'Seek help through patience.');
    });

    test('formats a hadith citation', () {
      final result = RagSearchResult(
        type: RagSourceType.hadith,
        score: 1,
        hadith: Hadith(
          id: 1,
          bookName: 'Sahih al-Bukhari',
          hadithNumber: '1',
          chapterTitle: 'Revelation',
          arabicText: 'عربي',
          englishText: 'Actions are but by intention.',
          banglaText: 'বাংলা',
        ),
      );
      final citation = citationFor(result);
      expect(citation.title, 'Sahih al-Bukhari Hadith 1');
      expect(citation.text, 'Actions are but by intention.');
    });

    test('formats a tafsir-chunk citation with the real surah name', () {
      final result = RagSearchResult(
        type: RagSourceType.tafsir,
        score: 1,
        tafsir: TafsirChunk(
          id: 1,
          tafsirId: 1,
          surahNumber: 1,
          ayahNumber: 1,
          author: 'Ibn Kathir',
          chunkIndex: 0,
          contentEnglish: 'Commentary on the Basmalah.',
        ),
      );
      final citation = citationFor(result);
      expect(citation.title, 'Tafsir Al-Fatiha 1:1');
      expect(citation.text, 'Commentary on the Basmalah.');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/repositories/rag_repository_test.dart`
Expected: FAIL — `db.tafsirChunks` doesn't exist yet on `RagSearchResult`/compile errors referencing `citationFor`, `TafsirChunk`.

- [ ] **Step 3: Replace `rag_repository.dart`**

Replace the entire contents of `lib/data/repositories/rag_repository.dart`:

```dart
import 'dart:math';
import 'dart:typed_data';
import '../local/db/knowledge_base_database.dart';
import '../../core/services/embedding_service.dart';
import '../../core/services/bm25_index.dart';
import '../../core/theme/quran_data.dart';

enum RagSourceType { verse, hadith, tafsir }

class RagSearchResult {
  final RagSourceType type;
  final double score;
  final Verse? verse;
  final Hadith? hadith;
  final TafsirChunk? tafsir;

  RagSearchResult({
    required this.type,
    required this.score,
    this.verse,
    this.hadith,
    this.tafsir,
  });
}

/// A citation ready for display or for inclusion in an LLM prompt.
class RagCitation {
  final String title;
  final String text;
  const RagCitation({required this.title, required this.text});
}

/// English name for surah [number] (1-114), e.g. 'Al-Fatiha'. Falls back to
/// the bare number if it's out of range (shouldn't happen with real KB data).
String _surahName(int number) {
  if (number < 1 || number > quranSurahs.length) return '$number';
  return quranSurahs[number - 1]['nameEn'] as String;
}

/// Builds the citation label/text for a [RagSearchResult] — shared by the UI
/// (citation chips, qa_agent_screen.dart) and LlmService (the "Reference
/// material" it grounds answers in), so the two can never drift out of sync.
RagCitation citationFor(RagSearchResult result) {
  switch (result.type) {
    case RagSourceType.verse:
      final verse = result.verse!;
      return RagCitation(
        title: 'Surah ${_surahName(verse.surahNumber)} ${verse.surahNumber}:${verse.ayahNumber}',
        text: verse.englishText,
      );
    case RagSourceType.hadith:
      final hadith = result.hadith!;
      return RagCitation(
        title: '${hadith.bookName} Hadith ${hadith.hadithNumber}',
        text: hadith.englishText,
      );
    case RagSourceType.tafsir:
      final tafsir = result.tafsir!;
      return RagCitation(
        title: 'Tafsir ${_surahName(tafsir.surahNumber)} ${tafsir.surahNumber}:${tafsir.ayahNumber}',
        text: tafsir.contentEnglish,
      );
  }
}

/// Hybrid retrieval over the offline knowledge base: fuses embedding
/// similarity (an in-memory, SIMD-accelerated scan — see [_ensureEmbeddingCache])
/// with BM25 keyword search ([Bm25Index]) via Reciprocal Rank Fusion.
class RagRepository {
  final KnowledgeBaseDatabase _db;
  final EmbeddingService _embeddingService;
  late final Bm25Index _bm25Index;

  static const int hadithOffset = 100000;
  static const int tafsirOffset = 200000;
  static const int _embeddingDimensions = 384;
  static const int _rrfK = 60;

  Float32List? _embeddingMatrix;
  List<int>? _embeddingDocIds;

  RagRepository(this._db, this._embeddingService) {
    _bm25Index = Bm25Index(_db);
  }

  /// Loads every stored embedding into one flat, contiguous [Float32List]
  /// (docCount × 384) plus a parallel doc-id list, once. Replaces the old
  /// per-query `SELECT * FROM vec_knowledge_base` (the dominant cost of the
  /// previous implementation) — this cache lives for the repository's
  /// lifetime, which is naturally rebuilt whenever the KB is re-downloaded
  /// (see database_provider.dart's ref.invalidate wiring).
  Future<void> _ensureEmbeddingCache() async {
    if (_embeddingMatrix != null) return;

    final rows = await _db.customSelect('SELECT rowid, embedding FROM vec_knowledge_base').get();
    final docIds = <int>[];
    final matrix = Float32List(rows.length * _embeddingDimensions);

    for (var i = 0; i < rows.length; i++) {
      final rowid = rows[i].read<int>('rowid');
      final blob = rows[i].read<Uint8List>('embedding');
      final floats = Float32List.sublistView(blob);
      docIds.add(rowid);
      final offset = i * _embeddingDimensions;
      final count = min(_embeddingDimensions, floats.length);
      for (var d = 0; d < count; d++) {
        matrix[offset + d] = floats[d];
      }
    }

    _embeddingDocIds = docIds;
    _embeddingMatrix = matrix;
  }

  /// SIMD dot product (4 floats/lane) between [queryLanes] and the doc
  /// embedding stored at [docIndex] in [matrix]. 384 divides evenly into 96
  /// lanes, so there's no remainder to handle separately.
  double _dotProduct(Float32x4List queryLanes, Float32List matrix, int docIndex) {
    final base = docIndex * _embeddingDimensions;
    var sum = Float32x4.zero();
    for (var lane = 0; lane < queryLanes.length; lane++) {
      final matrixOffset = base + lane * 4;
      final docLane = Float32x4(
        matrix[matrixOffset],
        matrix[matrixOffset + 1],
        matrix[matrixOffset + 2],
        matrix[matrixOffset + 3],
      );
      sum += queryLanes[lane] * docLane;
    }
    return sum.x + sum.y + sum.z + sum.w;
  }

  Future<List<MapEntry<int, double>>> _embeddingSearch(String query, {int limit = 20}) async {
    await _ensureEmbeddingCache();
    final docIds = _embeddingDocIds!;
    final matrix = _embeddingMatrix!;
    if (docIds.isEmpty) return const [];

    final queryVector = await _embeddingService.getEmbedding(query, isQuery: true);
    final queryFloats = Float32List.fromList(queryVector);
    final laneCount = _embeddingDimensions ~/ 4;
    final queryLanes = Float32x4List(laneCount);
    for (var lane = 0; lane < laneCount; lane++) {
      final offset = lane * 4;
      queryLanes[lane] = Float32x4(
        queryFloats[offset],
        queryFloats[offset + 1],
        queryFloats[offset + 2],
        queryFloats[offset + 3],
      );
    }

    final scored = <MapEntry<int, double>>[];
    for (var i = 0; i < docIds.length; i++) {
      scored.add(MapEntry(docIds[i], _dotProduct(queryLanes, matrix, i)));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).toList();
  }

  /// Fuses two ranked (docId, score) lists via Reciprocal Rank Fusion —
  /// score depends only on rank position, so BM25 scores and dot-product
  /// scores never need to be rescaled against each other. A doc present in
  /// only one list still accumulates a score from that list alone.
  List<MapEntry<int, double>> _reciprocalRankFusion(
    List<MapEntry<int, double>> a,
    List<MapEntry<int, double>> b, {
    required int limit,
  }) {
    final fused = <int, double>{};
    for (var rank = 0; rank < a.length; rank++) {
      final docId = a[rank].key;
      fused[docId] = (fused[docId] ?? 0) + 1 / (_rrfK + rank + 1);
    }
    for (var rank = 0; rank < b.length; rank++) {
      final docId = b[rank].key;
      fused[docId] = (fused[docId] ?? 0) + 1 / (_rrfK + rank + 1);
    }
    final ranked = fused.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
    return ranked.take(limit).toList();
  }

  /// Hybrid retrieval: fuses embedding similarity with BM25 keyword search,
  /// then hydrates the fused top-[limit] ids into full verse/hadith/
  /// tafsir-chunk rows.
  Future<List<RagSearchResult>> search(String query, {int limit = 5}) async {
    final embeddingResults = await _embeddingSearch(query, limit: 20);
    final bm25Results = await _bm25Index.search(query, limit: 20);
    final fused = _reciprocalRankFusion(embeddingResults, bm25Results, limit: limit);

    final searchResults = <RagSearchResult>[];
    for (final entry in fused) {
      final match = await _buildSearchResult(entry.key, entry.value);
      if (match.verse != null || match.hadith != null || match.tafsir != null) {
        searchResults.add(match);
      }
    }
    return searchResults;
  }

  Future<RagSearchResult> _buildSearchResult(int rowid, double score) async {
    if (rowid < hadithOffset) {
      final verse = await (_db.select(_db.verses)..where((t) => t.id.equals(rowid))).getSingleOrNull();
      return RagSearchResult(type: RagSourceType.verse, score: score, verse: verse);
    } else if (rowid >= hadithOffset && rowid < tafsirOffset) {
      final hadithId = rowid - hadithOffset;
      final hadith = await (_db.select(_db.hadiths)..where((t) => t.id.equals(hadithId))).getSingleOrNull();
      return RagSearchResult(type: RagSourceType.hadith, score: score, hadith: hadith);
    } else {
      final tafsirChunkId = rowid - tafsirOffset;
      final tafsirChunk =
          await (_db.select(_db.tafsirChunks)..where((t) => t.id.equals(tafsirChunkId))).getSingleOrNull();
      return RagSearchResult(type: RagSourceType.tafsir, score: score, tafsir: tafsirChunk);
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/repositories/rag_repository_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Run the full test suite to check for regressions in other consumers**

Run: `flutter test`
Expected: some failures in `test/presentation/screens/qa_agent_screen_test.dart` or `test/core/services/llm_service_test.dart` are NOT expected yet since those files don't reference `RagRepository` directly. If `flutter analyze` reports errors in `lib/presentation/screens/qa_agent_screen.dart` about `res.tafsir!.contentEnglish` or similar, that's expected and fixed in Task 7 — do not fix it here.

Run: `flutter analyze`
Expected: errors only in `lib/presentation/screens/qa_agent_screen.dart` (fixed in Task 7). No errors anywhere else.

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/rag_repository.dart test/data/repositories/rag_repository_test.dart
git commit -m "feat(rag): hybrid embedding+BM25 search with in-memory SIMD cache and RRF fusion"
```

---

### Task 5: `tool/build_kb.dart` — tafsir chunking + BM25 index computation

**Files:**
- Modify: `tool/build_kb.dart`
- Modify: `lib/core/services/embedding_service.dart` (add `countTokensSync`)

**Interfaces:**
- Consumes: `chunkText`, `tokenizeForBm25` (Task 1); `TafsirChunks`, `Bm25Postings`, `Bm25DocStats` (Task 2).
- Produces: a `kb.db` file with `tafsir_chunks` populated (chunked) alongside the untouched `tafsirs` table, `vec_knowledge_base` embeddings computed over chunks instead of whole tafsir entries, and `bm25_postings`/`bm25_doc_stats`/`kb_meta` (`bm25_doc_count`, `bm25_avg_doc_length`) populated for every verse/hadith/tafsir-chunk.

- [ ] **Step 1: Add `countTokensSync` to `EmbeddingService`**

Modify `lib/core/services/embedding_service.dart` — add this method to the `EmbeddingService` class, right after `getEmbedding`:

```dart
  /// Synchronous, exact token count for [text] using the already-loaded
  /// tokenizer — callers MUST call [init] first (throws otherwise). Used by
  /// tool/build_kb.dart's tafsir chunker, which needs precise token counts
  /// in a tight, non-async loop rather than a word-count approximation.
  /// Adds 2 for the [CLS]/[SEP] special tokens `getEmbedding` also adds, so
  /// the count matches the real sequence length fed to the model.
  int countTokensSync(String text) {
    if (!_initialized) {
      throw StateError('EmbeddingService.countTokensSync called before init()');
    }
    if (_useMock) {
      return text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length + 2;
    }
    return _tokenizer!.tokenize(text).length + 2;
  }
```

- [ ] **Step 2: Run existing embedding tests to confirm no regression**

Run: `flutter test test/core/services/embedding_service_test.dart`
Expected: PASS (existing 4 tests unaffected — this only adds a new method)

- [ ] **Step 3: Update `tool/build_kb.dart` imports and `main()`**

Modify `tool/build_kb.dart` — add imports after the existing `import 'kb_sources.dart' as kbsrc;` line:

```dart
import 'package:learn_quran/core/utils/text_chunking.dart';
import 'package:learn_quran/core/utils/bm25_tokenizer.dart';
```

Then update `main()`'s body — replace:

```dart
    stdout.writeln('Fetching Tafsir Ibn Kathir (English/Bangla)...');
    await _fetchAndInsertTafsir(db, client);

    stdout.writeln('Embedding English text (this takes a while for the full corpus)...');
    await _embedAndIndex(db, embeddingService);
```

with:

```dart
    stdout.writeln('Fetching Tafsir Ibn Kathir (English/Bangla) and chunking long entries...');
    await embeddingService.init();
    await _fetchAndInsertTafsir(db, client, embeddingService);

    stdout.writeln('Embedding English text and building the BM25 index (this takes a while for the full corpus)...');
    await _embedAndIndex(db, embeddingService);
```

- [ ] **Step 4: Chunk tafsir entries when inserting**

Modify `tool/build_kb.dart` — replace the entire `_fetchAndInsertTafsir` function:

```dart
Future<void> _fetchAndInsertTafsir(
  KnowledgeBaseDatabase db,
  http.Client client,
  EmbeddingService embeddingService,
) async {
  var tafsirId = 1;
  var chunkId = 1;
  var totalChunks = 0;
  var totalEntries = 0;

  for (var surahNumber = 1; surahNumber <= 114; surahNumber++) {
    final englishResponse =
        await client.get(Uri.parse('${kbsrc.tafsirBaseUrl}/${kbsrc.tafsirEnglishSlug}/$surahNumber.json'));
    final banglaResponse =
        await client.get(Uri.parse('${kbsrc.tafsirBaseUrl}/${kbsrc.tafsirBanglaSlug}/$surahNumber.json'));
    final english = kbsrc.parseTafsirSurah(jsonDecode(englishResponse.body));
    final bangla = kbsrc.parseTafsirSurah(jsonDecode(banglaResponse.body));

    for (var i = 0; i < english.length; i++) {
      await db.into(db.tafsirs).insert(TafsirsCompanion.insert(
            id: Value(tafsirId),
            surahNumber: surahNumber,
            ayahNumber: english[i].ayahNumber,
            author: 'Ibn Kathir',
            contentEnglish: english[i].text,
            contentBangla: i < bangla.length ? bangla[i].text : '',
          ));

      final chunks = chunkText(
        english[i].text,
        maxTokens: 200,
        countTokens: embeddingService.countTokensSync,
      );
      totalEntries++;
      totalChunks += chunks.length;
      for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
        await db.into(db.tafsirChunks).insert(TafsirChunksCompanion.insert(
              id: Value(chunkId),
              tafsirId: tafsirId,
              surahNumber: surahNumber,
              ayahNumber: english[i].ayahNumber,
              author: 'Ibn Kathir',
              chunkIndex: chunkIndex,
              contentEnglish: chunks[chunkIndex],
            ));
        chunkId++;
      }

      tafsirId++;
    }
  }

  stdout.writeln('  Tafsir: $totalEntries entries -> $totalChunks chunks '
      '(${totalChunks - totalEntries} entries split into multiple chunks)');
}
```

- [ ] **Step 5: Embed chunks and compute BM25 stats**

Modify `tool/build_kb.dart` — replace the entire `_embedAndIndex` function:

```dart
/// Embeds every verse/hadith/tafsir-chunk's English text into
/// vec_knowledge_base, and computes the BM25 term-frequency/document-length
/// statistics into bm25_postings/bm25_doc_stats/kb_meta — both using the
/// same hadithOffset/tafsirOffset rowid scheme RagRepository.search() reads.
Future<void> _embedAndIndex(KnowledgeBaseDatabase db, EmbeddingService embeddingService) async {
  const hadithOffset = 100000;
  const tafsirOffset = 200000;

  final docLengths = <int, int>{};
  final termFrequenciesByDoc = <int, Map<String, int>>{};

  Future<void> indexDoc(int docId, String text) async {
    final embedding = await embeddingService.getEmbedding(text);
    await _insertVector(db, docId, embedding);

    final tokens = tokenizeForBm25(text);
    docLengths[docId] = tokens.length;
    final freq = <String, int>{};
    for (final token in tokens) {
      freq[token] = (freq[token] ?? 0) + 1;
    }
    termFrequenciesByDoc[docId] = freq;
  }

  final verses = await db.select(db.verses).get();
  for (final verse in verses) {
    await indexDoc(verse.id, verse.englishText);
  }

  final hadiths = await db.select(db.hadiths).get();
  for (final hadith in hadiths) {
    await indexDoc(hadithOffset + hadith.id, hadith.englishText);
  }

  final tafsirChunks = await db.select(db.tafsirChunks).get();
  for (final chunk in tafsirChunks) {
    await indexDoc(tafsirOffset + chunk.id, chunk.contentEnglish);
  }

  stdout.writeln('Building BM25 index (${termFrequenciesByDoc.length} documents)...');
  await db.batch((batch) {
    for (final entry in termFrequenciesByDoc.entries) {
      final docId = entry.key;
      for (final termEntry in entry.value.entries) {
        batch.insert(
          db.bm25Postings,
          Bm25PostingsCompanion.insert(term: termEntry.key, docId: docId, termFrequency: termEntry.value),
        );
      }
      batch.insert(
        db.bm25DocStats,
        Bm25DocStatsCompanion.insert(docId: docId, docLength: docLengths[docId]!),
      );
    }
  });

  final avgDocLength = docLengths.values.isEmpty
      ? 0.0
      : docLengths.values.reduce((a, b) => a + b) / docLengths.values.length;
  await db.into(db.kbMeta).insert(
        KbMetaCompanion.insert(key: 'bm25_doc_count', value: termFrequenciesByDoc.length.toString()),
      );
  await db.into(db.kbMeta).insert(
        KbMetaCompanion.insert(key: 'bm25_avg_doc_length', value: avgDocLength.toString()),
      );
}
```

- [ ] **Step 6: Run `flutter analyze` on the whole project**

Run: `flutter analyze`
Expected: No issues in `tool/build_kb.dart` or `lib/core/services/embedding_service.dart`. (`lib/presentation/screens/qa_agent_screen.dart` errors from Task 4 are still expected here — fixed in Task 7.)

- [ ] **Step 7: Smoke-test the real build against live sources**

This step hits real, live public APIs (alquran.cloud, fawazahmed0/hadith-api, spa5k/tafsir_api) — same as the original KB v1 build did. `dart run tool/build_kb.dart` cannot work standalone (needs `rootBundle`/Flutter engine bindings for `EmbeddingService`), so it must run under `flutter test`'s `tool/build_kb_runner.dart` harness:

Run:
```bash
flutter test tool/build_kb_runner.dart --timeout=none \
  --dart-define=KB_OUTPUT=/tmp/kb_smoke_test.db --dart-define=KB_VERSION=1.1.0-smoke
```
Expected: completes without error, prints tafsir chunk counts (`Tafsir: N entries -> M chunks`) and `Building BM25 index (... documents)...`, ends with `Done: /tmp/kb_smoke_test.db`.

Then verify the output file directly:
```bash
sqlite3 /tmp/kb_smoke_test.db "SELECT COUNT(*) FROM tafsir_chunks;"
sqlite3 /tmp/kb_smoke_test.db "SELECT COUNT(*) FROM bm25_postings;"
sqlite3 /tmp/kb_smoke_test.db "SELECT value FROM kb_meta WHERE key = 'bm25_doc_count';"
sqlite3 /tmp/kb_smoke_test.db "SELECT COUNT(*) FROM vec_knowledge_base;"
rm /tmp/kb_smoke_test.db
```
Expected: `tafsir_chunks` count ≥ the tafsir entry count (6236) since some entries split into multiple chunks; `bm25_postings` has a large number of rows (one per unique term per document); `bm25_doc_count` matches `vec_knowledge_base`'s row count (every embedded doc also has BM25 stats).

- [ ] **Step 8: Commit**

```bash
git add tool/build_kb.dart lib/core/services/embedding_service.dart
git commit -m "feat(kb-build): chunk long tafsir entries and precompute the BM25 index"
```

---

### Task 6: `LlmService` — generate-retrieve-refine orchestration

**Files:**
- Modify: `lib/core/services/llm_service.dart`
- Test: `test/core/services/llm_service_test.dart`

**Interfaces:**
- Consumes: `RagRepository`, `RagSearchResult`, `citationFor` (Task 4).
- Produces: `LlmService.generateGroundedResponseStream(String question, {required RagRepository ragRepository, void Function(List<RagSearchResult>)? onRetrieved}) -> Stream<String>` — used by Task 7 (`qa_agent_screen.dart`). `LlmService`'s constructor gains an optional 3rd positional parameter, a `ChatOrNullFn?`, for testing — existing call sites (`LlmService()`, `LlmService(userRepo)`, `LlmService(userRepo, downloadService)`) are unaffected.

- [ ] **Step 1: Write the failing tests**

Modify `test/core/services/llm_service_test.dart` — add these imports at the top:

```dart
import 'package:drift/drift.dart' as drift;
import 'package:learn_quran/data/local/db/knowledge_base_database.dart';
import 'package:learn_quran/data/repositories/rag_repository.dart';
import 'package:learn_quran/core/services/embedding_service.dart';
```

Add this helper near the top of the file, after `_createFakeDownloadedFile`:

```dart
/// A RagRepository test double that records every query it's asked to
/// search, without touching a real database — used to verify
/// generateGroundedResponseStream picks the right retrieval query (the
/// draft, or the raw question on draft failure) without depending on
/// embedding-similarity behavior.
class _RecordingRagRepository extends RagRepository {
  final List<String> queries = [];
  _RecordingRagRepository(KnowledgeBaseDatabase db, EmbeddingService embeddingService) : super(db, embeddingService);

  @override
  Future<List<RagSearchResult>> search(String query, {int limit = 5}) async {
    queries.add(query);
    return const [];
  }
}
```

Add this new group inside `void main()`, after the existing `group('LlmService Tests', ...)` block (still inside `void main()`, as a sibling group):

```dart
  group('LlmService.generateGroundedResponseStream', () {
    late KnowledgeBaseDatabase kbDb;
    late EmbeddingService embeddingService;

    setUp(() {
      kbDb = KnowledgeBaseDatabase.forTesting(NativeDatabase.memory());
      embeddingService = EmbeddingService(forceMock: true);
    });

    tearDown(() async {
      await kbDb.close();
    });

    test('with no chat override (no model downloaded), retrieves on the raw question and streams the mock response', () async {
      final llm = LlmService(userRepo, downloadService);
      final recordingRepo = _RecordingRagRepository(kbDb, embeddingService);

      final stream = llm.generateGroundedResponseStream(
        'What does the Quran say about patience?',
        ragRepository: recordingRepo,
      );
      final response = await stream.join();

      expect(recordingRepo.queries, ['What does the Quran say about patience?']);
      expect(response, contains('As-Salamu Alaykum'));
    });

    test('with a chat override, retrieval uses the drafted text (HyDE), not the raw question', () async {
      final calls = <int>[];
      Future<Stream<String>?> chatOverride(String systemPrompt, String userPrompt, int maxTokens) async {
        calls.add(maxTokens);
        if (maxTokens == 150) return Stream.value('a hypothetical draft answer');
        return Stream.value('Final grounded answer.');
      }
      final llm = LlmService(userRepo, downloadService, chatOverride);
      final recordingRepo = _RecordingRagRepository(kbDb, embeddingService);

      final stream = llm.generateGroundedResponseStream(
        'the original question',
        ragRepository: recordingRepo,
      );
      final response = await stream.join();

      expect(calls, [150, 512]);
      expect(recordingRepo.queries, ['a hypothetical draft answer']);
      expect(response, 'Final grounded answer.');
    });

    test('falls back to the raw question for retrieval if the draft pass throws', () async {
      Future<Stream<String>?> chatOverride(String systemPrompt, String userPrompt, int maxTokens) async {
        if (maxTokens == 150) throw Exception('simulated draft failure');
        return Stream.value('Final grounded answer.');
      }
      final llm = LlmService(userRepo, downloadService, chatOverride);
      final recordingRepo = _RecordingRagRepository(kbDb, embeddingService);

      final stream = llm.generateGroundedResponseStream(
        'the original question',
        ragRepository: recordingRepo,
      );
      final response = await stream.join();

      expect(recordingRepo.queries, ['the original question']);
      expect(response, 'Final grounded answer.');
    });

    test('the refine pass always answers the original question, never the draft', () async {
      final capturedUserPrompts = <String>[];
      Future<Stream<String>?> chatOverride(String systemPrompt, String userPrompt, int maxTokens) async {
        capturedUserPrompts.add(userPrompt);
        if (maxTokens == 150) return Stream.value('a hypothetical draft answer');
        return Stream.value('Final grounded answer.');
      }
      final llm = LlmService(userRepo, downloadService, chatOverride);
      final recordingRepo = _RecordingRagRepository(kbDb, embeddingService);

      final stream = llm.generateGroundedResponseStream(
        'the original question',
        ragRepository: recordingRepo,
      );
      await stream.join();

      expect(capturedUserPrompts, ['the original question', 'the original question']);
    });

    test('onRetrieved fires with the results generateGroundedResponseStream retrieved', () async {
      Future<Stream<String>?> chatOverride(String systemPrompt, String userPrompt, int maxTokens) async {
        if (maxTokens == 150) return Stream.value('draft');
        return Stream.value('answer');
      }
      final llm = LlmService(userRepo, downloadService, chatOverride);
      final recordingRepo = _RecordingRagRepository(kbDb, embeddingService);
      List<RagSearchResult>? retrieved;

      final stream = llm.generateGroundedResponseStream(
        'question',
        ragRepository: recordingRepo,
        onRetrieved: (results) => retrieved = results,
      );
      await stream.join();

      expect(retrieved, isNotNull);
      expect(retrieved, isEmpty); // _RecordingRagRepository always returns const []
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/services/llm_service_test.dart`
Expected: FAIL — `The method 'generateGroundedResponseStream' isn't defined for the type 'LlmService'` / `too many positional arguments` for the 3-arg `LlmService(...)` calls.

- [ ] **Step 3: Refactor `LlmService`**

Replace the entire contents of `lib/core/services/llm_service.dart`:

```dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llamadart/llamadart.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/rag_repository.dart';
import '../providers/repository_providers.dart';
import '../models/model_catalog.dart';
import 'model_download_service.dart';

/// Resolves a model, loads it if needed, and streams a chat completion — or
/// returns null if no model is available. Overridable for testing: the real
/// default resolves+loads the actual llama.cpp engine, which needs a real
/// multi-GB GGUF file no test environment has, so tests inject a fake that
/// never touches llamadart at all.
typedef ChatOrNullFn = Future<Stream<String>?> Function(
  String systemPrompt,
  String userPrompt,
  int maxTokens,
);

class LlmService {
  final UserRepository? _userRepo;
  final ModelDownloadService _downloadService;
  final ChatOrNullFn? _chatOverride;
  LlamaEngine? _engine;
  String? _loadedModelPath;

  LlmService([this._userRepo, ModelDownloadService? downloadService, ChatOrNullFn? chatOverride])
      : _downloadService = downloadService ?? ModelDownloadService(),
        _chatOverride = chatOverride;

  ChatOrNullFn get _chat => _chatOverride ?? _defaultChatOrNull;

  /// Resolves the user's selected model (or the RAM-based recommendation if
  /// nothing's been explicitly selected), then returns its local file path
  /// if it's actually downloaded — or null if it isn't (or if resolving that
  /// even fails, e.g. no platform plugin binding available), so callers
  /// always have a safe mock/no-model fallback rather than crashing.
  Future<String?> getSelectedModelPath() async {
    try {
      final model = await _resolveSelectedModel();
      if (await _downloadService.isDownloaded(model)) {
        return _downloadService.localPathFor(model);
      }
    } catch (_) {}
    return null;
  }

  Future<ModelInfo> _resolveSelectedModel() async {
    if (_userRepo != null) {
      final selectedId = await _userRepo.getEngagementValue('selected_llm_model');
      if (selectedId != null) {
        return modelById(selectedId);
      }
    }
    return recommendedModelFor(detectDeviceRamGb());
  }

  /// Reads total device RAM from `/proc/meminfo`, which is world-readable
  /// on both desktop Linux and Android (both are Linux-kernel-based) —
  /// no platform-specific plugin or permission needed. Falls back to a
  /// conservative 4.0GB estimate on any other platform or read failure.
  double detectDeviceRamGb() {
    try {
      if (Platform.isLinux || Platform.isAndroid) {
        final meminfo = File('/proc/meminfo');
        if (meminfo.existsSync()) {
          final lines = meminfo.readAsLinesSync();
          for (final line in lines) {
            if (line.startsWith('MemTotal:')) {
              final match = RegExp(r'\d+').firstMatch(line);
              if (match != null) {
                final totalKb = int.parse(match.group(0)!);
                return totalKb / (1024 * 1024);
              }
            }
          }
        }
      }
    } catch (_) {}
    return 4.0; // Default fallback
  }

  /// Loads (or reuses an already-loaded) llama.cpp engine for [modelPath].
  /// Returns null if loading fails for any reason (corrupt file, OOM,
  /// unsupported quantization, ...), so callers fall back to mock responses
  /// instead of crashing the whole Q&A flow.
  Future<LlamaEngine?> _ensureEngine(String modelPath) async {
    if (_engine != null && _loadedModelPath == modelPath) {
      return _engine;
    }

    if (_engine != null) {
      await _engine!.dispose();
      _engine = null;
      _loadedModelPath = null;
    }

    try {
      final engine = LlamaEngine(LlamaBackend());
      await engine.loadModel(modelPath, modelParams: const ModelParams(contextSize: 4096));
      _engine = engine;
      _loadedModelPath = modelPath;
      return engine;
    } catch (_) {
      _engine = null;
      _loadedModelPath = null;
      return null;
    }
  }

  Future<Stream<String>?> _defaultChatOrNull(String systemPrompt, String userPrompt, int maxTokens) async {
    final modelPath = await getSelectedModelPath();
    final engine = modelPath == null ? null : await _ensureEngine(modelPath);
    if (engine == null) return null;
    return _streamChat(engine, systemPrompt, userPrompt, maxTokens);
  }

  Stream<String> _streamChat(LlamaEngine engine, String systemPrompt, String userPrompt, int maxTokens) async* {
    final messages = [
      LlamaChatMessage.fromText(role: LlamaChatRole.system, text: systemPrompt),
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: userPrompt),
    ];
    final responseStream = engine.create(
      messages,
      params: GenerationParams(maxTokens: maxTokens, temp: 0.7, topP: 0.9),
    );
    await for (final chunk in responseStream) {
      final text = chunk.choices.isNotEmpty ? chunk.choices.first.delta.content : null;
      if (text != null && text.isNotEmpty) {
        yield text;
      }
    }
  }

  /// Releases the loaded model's native resources. Call when the owning
  /// provider is disposed (app teardown / hot restart).
  Future<void> dispose() async {
    await _engine?.dispose();
    _engine = null;
    _loadedModelPath = null;
  }

  /// Single-pass generation: streams a response for [prompt], grounded in
  /// [ragContext] if non-empty. Falls back to a hardcoded mock response if
  /// no model is downloaded/loaded. Used directly by DailyStoryService (no
  /// RAG involved there) and as the final "refine" pass of
  /// [generateGroundedResponseStream].
  Stream<String> generateResponseStream(String prompt, String ragContext) async* {
    final chatStream = await _chat(_systemPrompt(ragContext), prompt, 512);
    if (chatStream == null) {
      final responseText = _generateMockResponse(prompt, ragContext);
      final words = responseText.split(' ');
      for (final word in words) {
        await Future.delayed(const Duration(milliseconds: 50));
        yield '$word ';
      }
      return;
    }
    yield* chatStream;
  }

  static const _draftSystemPrompt =
      'You are a gentle, respectful Islamic teaching companion. Answer the '
      "question briefly and naturally from your own general knowledge — you "
      'do not need to cite sources or worry about accuracy for this answer.';

  /// Two-pass, RAG-grounded generation for the Q&A screen:
  /// 1. A short, hidden draft answer from the model's own knowledge (HyDE —
  ///    a hypothetical answer retrieves better than the raw question).
  /// 2. Hybrid retrieval ([ragRepository.search]) using that draft as the
  ///    query.
  /// 3. The same single-pass [generateResponseStream] as the final "refine"
  ///    pass, grounded in the retrieved references and answering the
  ///    original [question] — never the draft.
  ///
  /// Degrades gracefully: if no model is available, [_chat] returns null for
  /// the draft, so retrieval runs on the raw [question] and
  /// [generateResponseStream] falls through to its own existing mock path —
  /// no special-casing needed here. If the draft pass throws for any other
  /// reason, retrieval also falls back to the raw [question].
  Stream<String> generateGroundedResponseStream(
    String question, {
    required RagRepository ragRepository,
    void Function(List<RagSearchResult> ragResults)? onRetrieved,
  }) async* {
    var retrievalQuery = question;
    try {
      final draftStream = await _chat(_draftSystemPrompt, question, 150);
      if (draftStream != null) {
        final draft = (await draftStream.join()).trim();
        if (draft.isNotEmpty) retrievalQuery = draft;
      }
    } catch (_) {
      // Fall back to the raw question as the retrieval query.
    }

    final ragResults = await ragRepository.search(retrievalQuery, limit: 5);
    onRetrieved?.call(ragResults);
    final ragContext = _buildRagContext(ragResults);

    yield* generateResponseStream(question, ragContext);
  }

  String _buildRagContext(List<RagSearchResult> results) {
    final buffer = StringBuffer();
    for (final result in results) {
      final citation = citationFor(result);
      buffer.writeln('[${citation.title}] ${citation.text}');
    }
    return buffer.toString();
  }

  /// Encodes Rules.md's theological/AI generation rules (Sunnah Teaching
  /// Methodology, Zero-Hallucination Policy, Citations Required) as a system
  /// prompt for real on-device inference — the mock path already hardcodes
  /// this tone, so this keeps behavior consistent once a real model answers.
  String _systemPrompt(String ragContext) {
    final buffer = StringBuffer()
      ..writeln(
        'You are a gentle, respectful Islamic teaching companion for the Learn Quran app.',
      )
      ..writeln(
        'Always respond with warmth and clarity, in the manner of the Sunnah — '
        'never harsh, condescending, or clinical.',
      )
      ..writeln(
        'Base your answer only on the reference material below. If it does not '
        'contain enough information to answer, politely say you do not have '
        'enough information from your local sources rather than guessing.',
      )
      ..writeln(
        'When you use a verse or hadith from the material, cite it using the '
        'label given in brackets before it, for example "[Surah Al-Baqarah 2:153]".',
      );

    if (ragContext.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Reference material:')
        ..writeln(ragContext);
    }
    return buffer.toString();
  }

  String _generateMockResponse(String prompt, String ragContext) {
    final lowercasePrompt = prompt.toLowerCase();

    if (lowercasePrompt.contains('reflection') || lowercasePrompt.contains('story')) {
      return 'Title: Finding Calm in Patience\n\n'
             'As-Salamu Alaykum. In the journey of life, we often face moments of doubt and tiredness. '
             'However, every verse you read and every Salat you pray brings you closer to divine light. '
             'Remember, patience is a source of strength, and your consistency is beautiful to the Almighty. '
             'Keep moving forward with a peaceful heart, knowing that with every difficulty comes ease.';
    }

    if (lowercasePrompt.contains('patience') || lowercasePrompt.contains('sabr')) {
      return 'As-Salamu Alaykum. Patience (Sabr) is a beautiful virtue in Islam. '
             "Allah says in the Quran, 'Indeed, Allah is with the patient' (Surah Al-Baqarah 2:153). "
             'The Prophet Muhammad (peace be upon him) demonstrated patience throughout his life, '
             'responding to difficulties with calmness and prayers for those who opposed him. '
             "When facing adversity, we are encouraged to remain steadfast, trust in Allah's wisdom, and pray.";
    }

    if (lowercasePrompt.contains('sadness') || lowercasePrompt.contains('grief') || lowercasePrompt.contains('sorrow')) {
      return 'As-Salamu Alaykum. It is natural to feel sadness. Even the Prophet Muhammad (peace be upon him) experienced grief, '
             'such as during the Year of Sorrow. He taught us to turn to Allah in prayer. '
             "In the Quran, Allah comforts us: 'So verily, with every difficulty, there is relief' (Surah Ash-Sharh 94:5). "
             'Be gentle with yourself, keep praying, and know that Allah is close to the brokenhearted.';
    }

    if (lowercasePrompt.contains('salat') || lowercasePrompt.contains('prayer')) {
      return 'As-Salamu Alaykum. Salat is the second pillar of Islam and a direct connection to Allah. '
             "Allah mentions in the Quran: 'Establish prayer, for indeed prayer prohibits immorality and wrongdoing' (Surah Al-Ankabut 29:45). "
             'The Prophet (peace be upon him) described Salat as the coolness of his eyes, emphasizing its importance and beauty.';
    }

    if (ragContext.isNotEmpty) {
      return 'As-Salamu Alaykum. Based on the sacred texts: $ragContext. '
             'We should strive to understand and apply these teachings with sincerity, humility, and gentle manners, '
             'following the guidance of our Prophet Muhammad (peace be upon him).';
    }

    return 'As-Salamu Alaykum. May Allah grant you peace and understanding. '
           'Please let me know which verse, Hadith, or topic you would like to explore, '
           'and we will discuss it in a respectful and gentle way.';
  }
}

final llmServiceProvider = Provider<LlmService>((ref) {
  final userRepo = ref.watch(userRepositoryProvider);
  final service = LlmService(userRepo);
  ref.onDispose(() => service.dispose());
  return service;
});
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/services/llm_service_test.dart`
Expected: PASS (all previous tests plus the 5 new ones)

- [ ] **Step 5: Run the compliance and daily-story tests to confirm the mock/single-pass path is untouched**

Run: `flutter test test/core/services/llm_compliance_test.dart test/core/services/daily_story_service_test.dart`
Expected: PASS, unchanged from before this task

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/llm_service.dart test/core/services/llm_service_test.dart
git commit -m "feat(llm): generate-retrieve-refine orchestration (HyDE-style draft retrieval)"
```

---

### Task 7: Wire `qa_agent_screen.dart` to the new orchestration

**Files:**
- Modify: `lib/presentation/screens/qa_agent_screen.dart`

**Interfaces:**
- Consumes: `LlmService.generateGroundedResponseStream`, `citationFor` (Task 6, Task 4).
- Produces: nothing new — this is the final UI wiring, no other task depends on it.

- [ ] **Step 1: Remove the now-dead `_surahName` helper and its import**

Modify `lib/presentation/screens/qa_agent_screen.dart` — remove this import line:

```dart
import '../../core/theme/quran_data.dart';
```

Remove this function (citation formatting now lives in `rag_repository.dart`'s `citationFor`):

```dart
/// English name for surah [number] (1-114), e.g. 'Al-Fatiha'. Falls back to
/// the bare number if it's out of range (shouldn't happen with real KB data).
String _surahName(int number) {
  if (number < 1 || number > quranSurahs.length) return '$number';
  return quranSurahs[number - 1]['nameEn'] as String;
}
```

- [ ] **Step 2: Replace the RAG+LLM call in `_sendMessage`**

Modify `lib/presentation/screens/qa_agent_screen.dart` — inside `_sendMessage`, replace this entire block (from the `// 2. Perform RAG query` comment through the `// 4. Save final complete agent response to database` block, inclusive):

```dart
      // 2. Perform RAG query
      final ragResults = await ragRepo.search(text, limit: 3);
      
      final List<Map<String, String>> citationsList = [];
      final StringBuffer contextBuffer = StringBuffer();
      
      for (final res in ragResults) {
        String title = '';
        String textContent = '';
        
        if (res.type == RagSourceType.verse && res.verse != null) {
          title = 'Surah ${_surahName(res.verse!.surahNumber)} ${res.verse!.surahNumber}:${res.verse!.ayahNumber}';
          textContent = res.verse!.englishText;
        } else if (res.type == RagSourceType.hadith && res.hadith != null) {
          title = '${res.hadith!.bookName} Hadith ${res.hadith!.hadithNumber}';
          textContent = res.hadith!.englishText;
        } else if (res.type == RagSourceType.tafsir && res.tafsir != null) {
          title = 'Tafsir ${_surahName(res.tafsir!.surahNumber)} ${res.tafsir!.surahNumber}:${res.tafsir!.ayahNumber}';
          textContent = res.tafsir!.contentEnglish;
        }
        
        if (title.isNotEmpty) {
          citationsList.add({'title': title});
          // Label included so the model can cite its source per Rules.md.
          contextBuffer.writeln('[$title] $textContent');
        }
      }

      final citationsStr = citationsList.map((e) => e['title']!).join(' • ');
      final ragContext = contextBuffer.toString();

      // 3. Call LLM Service Stream
      final responseStream = llmService.generateResponseStream(text, ragContext);
      String fullAgentResponse = '';

      await for (final chunk in responseStream) {
        if (!mounted) return;
        fullAgentResponse += chunk;
        
        setState(() {
          _messages[_messages.length - 1] = {
            'sender': 'agent',
            'text': fullAgentResponse,
            'citations': citationsStr,
          };
        });
        _scrollToBottom();
      }

      // 4. Save final complete agent response to database
      await convoRepo.addMessage(
        _currentConversationId!,
        'agent',
        fullAgentResponse,
        jsonEncode(citationsList),
      );
```

with:

```dart
      // 2. Generate a grounded response: the LLM drafts from its own
      // knowledge first, that draft becomes the retrieval query (HyDE),
      // then the LLM refines its answer using the real retrieved
      // references — see LlmService.generateGroundedResponseStream.
      List<Map<String, String>> citationsList = [];
      String citationsStr = '';

      final responseStream = llmService.generateGroundedResponseStream(
        text,
        ragRepository: ragRepo,
        onRetrieved: (ragResults) {
          citationsList = [
            for (final result in ragResults) {'title': citationFor(result).title},
          ];
          citationsStr = citationsList.map((c) => c['title']!).join(' • ');
        },
      );
      String fullAgentResponse = '';

      await for (final chunk in responseStream) {
        if (!mounted) return;
        fullAgentResponse += chunk;

        setState(() {
          _messages[_messages.length - 1] = {
            'sender': 'agent',
            'text': fullAgentResponse,
            'citations': citationsStr,
          };
        });
        _scrollToBottom();
      }

      // 3. Save final complete agent response to database
      await convoRepo.addMessage(
        _currentConversationId!,
        'agent',
        fullAgentResponse,
        jsonEncode(citationsList),
      );
```

- [ ] **Step 3: Verify with static analysis**

Run: `flutter analyze`
Expected: No issues found — this was the last file with pending errors from Task 4's `RagSearchResult.tafsir` type change.

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`
Expected: All tests pass, including the pure-function tests in `test/presentation/screens/qa_agent_screen_test.dart` (`needsAiSetupPrompt`), which don't touch this code path.

Note: full widget-level testing of `qa_agent_screen.dart`'s chat flow is infeasible in this project's test environment (established precedent — Drift + fake-async + `google_fonts` friction), so this task's verification is `flutter analyze` + the full suite + manual reasoning about the diff, consistent with how this file was previously changed in this project.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/qa_agent_screen.dart
git commit -m "feat(qa): wire the Q&A screen to generate-retrieve-refine and shared citations"
```

---

### Task 8: Rebuild and release `kb-v1.1.0`, update `kb_catalog.dart`

**Files:**
- Modify: `lib/core/models/kb_catalog.dart`
- Modify: `test/core/models/kb_catalog_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1-6 (the full new build pipeline and schema).
- Produces: a real, published `kb-v1.1.0` GitHub Release; `kCurrentKb` pointing at it.

This task is operational (a real build + release), not pure code — it mirrors the `kb-v1.0.0`→`kb-v1.0.1` process already done twice in this project.

- [ ] **Step 1: Tag and push**

```bash
git tag -a kb-v1.1.0 -m "kb-v1.1.0: tafsir chunking + BM25 index for hybrid retrieval"
git push origin kb-v1.1.0
```

This triggers `.github/workflows/build-kb-on-tag.yml`, which runs the exact same `flutter test tool/build_kb_runner.dart` command as Task 5's smoke test, against the real full corpus, and publishes `kb.db`/`kb.db.sha256`/`kb.db.size` as release assets.

- [ ] **Step 2: Poll the workflow run**

```bash
curl -s "https://api.github.com/repos/gr0-o-0t/learn-quran/actions/runs?event=push&per_page=5"
```

Expected: a `Build and Publish Knowledge Base` run for `kb-v1.1.0` reaches `"status": "completed", "conclusion": "success"`. Prior full builds took roughly 12-15 minutes.

- [ ] **Step 3: Verify the release and fetch its real size/sha256**

```bash
curl -s "https://github.com/gr0-o-0t/learn-quran/releases/download/kb-v1.1.0/kb.db.sha256"
curl -s "https://github.com/gr0-o-0t/learn-quran/releases/download/kb-v1.1.0/kb.db.size"
```

Record both values exactly — they go into `kb_catalog.dart` in the next step. Do not guess or reuse the `kb-v1.0.1` values; this is a different file with a different size/hash.

- [ ] **Step 4: Update `kb_catalog.dart`**

Modify `lib/core/models/kb_catalog.dart` — update the doc comment and `kCurrentKb` with the real values from Step 3 (the placeholders `<REAL_SIZE>`/`<REAL_SHA256>` below MUST be replaced with the actual numbers, not left as-is):

```dart
/// The current knowledge base version the app knows how to fetch.
/// Verified against the real kb-v1.1.0 GitHub Release:
/// size <REAL_SIZE> bytes, sha256 <REAL_SHA256>.
/// v1.1.0 adds tafsir chunking (long commentary entries are split into
/// ~200-token chunks instead of being silently truncated at the 256-token
/// embedding limit) and a precomputed BM25 keyword index (see
/// tool/build_kb.dart, RagRepository, Bm25Index).
const KbInfo kCurrentKb = KbInfo(
  version: '1.1.0',
  filename: 'kb.db',
  sizeBytes: <REAL_SIZE>,
  sha256: '<REAL_SHA256>',
);
```

- [ ] **Step 5: Update the catalog test**

Modify `test/core/models/kb_catalog_test.dart` — update the hardcoded expectations to match the real Step 3 values:

```dart
  test('kCurrentKb.sizeBytes is filled in with the real published size', () {
    expect(kCurrentKb.sizeBytes, <REAL_SIZE>);
  });

  test('kCurrentKb.sha256 is a well-formed, correct 64-char lowercase hex digest', () {
    expect(kCurrentKb.sha256, hasLength(64));
    expect(kCurrentKb.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(
      kCurrentKb.sha256,
      '<REAL_SHA256>',
    );
  });
```

- [ ] **Step 6: Run the full test suite and analyze**

Run: `flutter analyze`
Expected: No issues found.

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 7: Commit and push**

```bash
git add lib/core/models/kb_catalog.dart test/core/models/kb_catalog_test.dart
git commit -m "chore(kb): pin real kb-v1.1.0 release values in kb_catalog.dart"
git push origin main
```

- [ ] **Step 8: Update `Tracker.md`**

Append a new bullet under the existing Phase 12 section in `Tracker.md` documenting this round: tafsir chunking, hybrid BM25+embedding retrieval, the generate-retrieve-refine flow, and the `kb-v1.1.0` release values — matching the style of the existing Phase 12 entries.

- [ ] **Step 9: Cut a new app release**

Since the app code (Tasks 4, 6, 7) works against either KB schema (BM25 degrades gracefully on an old `kb.db`), ordering isn't strictly forced, but shipping both together is cleanest:

```bash
git tag -a v1.3.0 -m "v1.3.0: tafsir chunking, hybrid BM25+embedding RAG retrieval, generate-retrieve-refine Q&A flow"
git push origin v1.3.0
```

Poll and verify exactly as done for prior app releases (`https://api.github.com/repos/gr0-o-0t/learn-quran/actions/runs?event=push`, then the release assets endpoint) — confirm all 6 jobs succeed and the release has all 8 platform assets before considering this task done.

---

## Self-Review Notes

- **Spec coverage**: tafsir chunking (Task 5), hybrid retrieval replacing brute force (Task 4), re-ranking via RRF (Task 4), BM25 keyword fallback (Tasks 1, 3, 4, 5), query rewriting via generate-retrieve-refine/HyDE (Task 6) — all five of the user's original asks are covered, plus the schema/release work the design requires (Tasks 2, 8).
- **`tafsirs` table safety**: Task 5 explicitly keeps inserting into `db.tafsirs` unchanged, alongside the new `db.tafsirChunks` — `QuranRepository.getTafsirForVerse()` is never touched.
- **Mock-path safety**: Task 6's refactor routes the existing mock behavior through the same `_chat`-returns-null path already proven by `test/core/services/llm_compliance_test.dart`; Task 6 Step 5 explicitly re-runs that suite to confirm.
- **Type consistency check**: `RagSearchResult.tafsir` is `TafsirChunk?` from Task 4 onward — Task 4's own tests, Task 6's `_buildRagContext`/`citationFor` usage, and Task 7's UI code were all written against this same type, not the old `Tafsir?`.
