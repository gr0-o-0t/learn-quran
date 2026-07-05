# Knowledge Base v1 (Content + Real Embeddings) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder 7-verse/1-hadith/1-tafsir database and fake (`Random(text.hashCode)`) embeddings with a complete, authentically-sourced Quran/Hadith/Tafsir knowledge base and real semantic embeddings, packaged into a versioned, always-read-only `kb.db` built by an offline tool and published via GitHub Releases.

**Architecture:** A new, separate `KnowledgeBaseDatabase` (Drift) holds `verses`/`hadiths`/`tafsirs`/`vec_knowledge_base`/`kb_meta` — read-only, distinct from `AppDatabase`'s user data. `EmbeddingService` is rewritten to use a real WordPiece tokenizer (`bert_tokenizer`) and a real ONNX model (BGE-small-en-v1.5) instead of the current fake char-code tokenizer and mock vectors. A new `tool/build_kb.dart` fetches real content from three verified public APIs, inserts it into a fresh `KnowledgeBaseDatabase` file, and reuses the existing (now-correct) `RagRepository.populateVectorIndex()` logic to embed it — producing `kb.db`. A GitHub Actions workflow runs this tool on `kb-v*` tags and publishes the result as a release asset. The app bundles the current `kb.db` as an asset (works offline from first launch) and a new `KbDownloadService`, mirroring `ModelDownloadService`, lets Settings pull newer versions.

**Tech Stack:** Flutter, Drift, `onnxruntime` (already a dependency), `bert_tokenizer` (new dependency), `http` (already a dependency), GitHub Actions.

See also: [docs/superpowers/specs/2026-07-05-knowledge-base-v1-design.md](../specs/2026-07-05-knowledge-base-v1-design.md) for the full design rationale, source verification trail, and decision log.

## Global Constraints

- Every content source must be real and verifiable — no fabricated or guessed API endpoints/identifiers. This plan only uses endpoints that were fetched and confirmed live during design (see the design doc's verification trail).
- Hindi is dropped entirely from `verses`/`hadiths`/`tafsirs` — no `hindi_text`/`hindiText`/`contentHindi` columns anywhere in the new schema.
- Embeddings are English-only.
- `vec_knowledge_base` is always built as the plain `(rowid INTEGER PRIMARY KEY, embedding BLOB)` shape, never a real `vec0` virtual table — `sqlite-vec` was found not to actually load in this environment (see design doc); building against the confirmed-working shape avoids depending on the unconfirmed one.
- `KnowledgeBaseDatabase` is read-only from the app's perspective — no repository method ever writes to its tables from within the running app.
- `flutter analyze` must stay at zero `error`-level issues; `flutter test` must stay fully green after every task.
- Hadith scope is Sahih al-Bukhari + Sahih Muslim only (not all six books).
- Tafsir scope is Tafsir Ibn Kathir only (English + Bengali).

---

### Task 1: `Rules.md` and `Schema.md` documentation updates

**Files:**
- Modify: `Rules.md`
- Modify: `Schema.md`

**Interfaces:** None (documentation only).

- [ ] **Step 1: Amend `Rules.md`'s "No Unapproved Networks" bullet**

In `Rules.md`, find this bullet under "## 2. Technical & Offline-First Constraints":

```markdown
*   **No Unapproved Networks:** Core packages must not make any external network requests. All dependencies (translations, databases) must reside locally in assets or application sandboxes. Exception: LLM model *files* may be fetched at runtime from Hugging Face, user-initiated, so users aren't forced to ship multi-GB weights in the app bundle. Once downloaded, all inference and RAG indexing still run fully on-device — no other network calls are introduced.
```

Replace it with:

```markdown
*   **No Unapproved Networks:** Core packages must not make any external network requests. All dependencies (translations, databases) must reside locally in assets or application sandboxes. Exception: LLM model *files* may be fetched at runtime from Hugging Face, user-initiated, so users aren't forced to ship multi-GB weights in the app bundle. Once downloaded, all inference and RAG indexing still run fully on-device — no other network calls are introduced. Exception: the Quran/Hadith/Tafsir knowledge base and its embeddings may also be fetched at runtime from a versioned, pinned GitHub Release, user-initiated, so corrections/expansions don't require a full app-store release. The initial knowledge base ships bundled as an asset so the app works fully offline from first launch — only updates are network-fetched.
```

- [ ] **Step 2: Amend `Schema.md`'s knowledge base section**

In `Schema.md`, replace the entire "## 1. Read-Only Knowledge Base Tables" section (from `## 1. Read-Only Knowledge Base Tables` through the blank line before `## 2. Writable User Data Tables`) with:

```markdown
## 1. Read-Only Knowledge Base Tables
These tables live in a separate, always-read-only database file (`kb.db`),
distinct from the user-data database below. The app never writes to them.
`kb.db` ships bundled as an app asset by default and can be updated from
Settings (see the knowledge-base-v1 design doc).

### 1.1. `verses`
Stores the Quran text, structural markers, and translations.
*   `id`: `INTEGER` (Primary Key)
*   `surah_number`: `INTEGER` (1-114)
*   `ayah_number`: `INTEGER`
*   `juz_number`: `INTEGER` (1-30)
*   `arabic_text`: `TEXT` (Uthmani script)
*   `english_text`: `TEXT` (Saheeh International)
*   `bangla_text`: `TEXT` (Muhiuddin Khan)

### 1.2. `hadiths`
Stores authentic Hadiths (Sahih al-Bukhari and Sahih Muslim only) for
referencing and the RAG pipeline.
*   `id`: `INTEGER` (Primary Key)
*   `book_name`: `TEXT` ('Sahih al-Bukhari' or 'Sahih Muslim')
*   `hadith_number`: `TEXT`
*   `chapter_title`: `TEXT`
*   `arabic_text`: `TEXT`
*   `english_text`: `TEXT`
*   `bangla_text`: `TEXT`

### 1.3. `tafsirs`
Tafsir Ibn Kathir commentary linked to verses.
*   `id`: `INTEGER` (Primary Key)
*   `surah_number`: `INTEGER` (Foreign Key -> `verses.surah_number`)
*   `ayah_number`: `INTEGER` (Foreign Key -> `verses.ayah_number`)
*   `author`: `TEXT` ('Ibn Kathir')
*   `content_english`: `TEXT`
*   `content_bangla`: `TEXT`

### 1.4. `kb_meta`
Single-row-per-key metadata describing this `kb.db` build.
*   `key`: `TEXT` (Primary Key) — e.g. `'version'`, `'built_at'`, `'embedding_model'`
*   `value`: `TEXT`

Note: Hindi translations/commentary are intentionally not included — no
authentic source was found for Hindi Hadith or Tafsir Ibn Kathir (see the
knowledge-base-v1 design doc's Decision Log). AI-translation-on-demand is a
deferred, separate feature.
```

- [ ] **Step 3: Amend `Schema.md`'s vector table section**

In `Schema.md`, find:

```markdown
## 3. SQLite-Vec (Virtual Tables for Vector Search)
Used for fast cosine-similarity search on embeddings.

### 3.1. `vec_knowledge_base`
Virtual table using the `sqlite-vec` extension to query embeddings.
*   `rowid`: `INTEGER` (Maps to row ID in `verses`, `hadiths`, or `tafsirs`)
*   `embedding`: `F32_BLOB` (Float32 vector array representing the segment embedding)
```

Replace it with:

```markdown
## 3. Vector Search Table
Lives in `kb.db` alongside the tables in section 1, precomputed at build
time (never generated on-device). Built as a plain table, not a `vec0`
virtual table — `sqlite-vec`'s native extension was found not to load in
the current dev/CI environment, so `RagRepository`'s existing Dart-side
dot-product fallback is the search path this table is built for.

### 3.1. `vec_knowledge_base`
*   `rowid`: `INTEGER` (Primary Key — maps to row ID in `verses`, `hadiths`, or `tafsirs`, using the existing `hadithOffset`/`tafsirOffset` scheme in `RagRepository`)
*   `embedding`: `BLOB` (384-dim float32 vector, English text only, from BGE-small-en-v1.5)
```

- [ ] **Step 4: Verify no other file references the old schema text**

Run: `grep -rn "hindi_text\|content_hindi" Schema.md Rules.md`
Expected: no output (both files fully updated).

- [ ] **Step 5: Commit**

```bash
git add Rules.md Schema.md
git commit -m "docs: amend Rules.md/Schema.md for the versioned, downloadable knowledge base"
```

---

### Task 2: Real embeddings — `bert_tokenizer` dependency + `EmbeddingService` rewrite

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/services/embedding_service.dart`
- Test: `test/core/services/embedding_service_test.dart`
- Create (asset, fetched manually — see Step 6): `assets/models/bge_small_en_v1_5.onnx`, `assets/models/bge_small_en_v1_5_vocab.txt`

**Interfaces:**
- Produces (used by Task 6's `tool/build_kb.dart` and existing `RagRepository`):
  - `class EmbeddingService` unchanged public surface except `Future<List<double>> getEmbedding(String text, {bool isQuery = false})` — new optional `isQuery` parameter, defaulting to `false` (matches existing call sites, which all embed passages/corpus text; `RagRepository.search()`'s query embedding call is updated in Task 6 to pass `isQuery: true`).

- [ ] **Step 1: Add the `bert_tokenizer` dependency**

In `pubspec.yaml`, add under the existing `dependencies:` block (after `onnxruntime: ^1.4.1`):

```yaml
  bert_tokenizer: ^1.1.1
```

Run: `flutter pub get`
Expected: resolves cleanly, `+ bert_tokenizer 1.1.1` in the output.

- [ ] **Step 2: Write the failing tokenizer test**

Create `test/core/services/embedding_service_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bert_tokenizer/bert_tokenizer.dart';
import 'package:learn_quran/core/services/embedding_service.dart';

const _miniVocab = '''
[PAD]
[UNK]
[CLS]
[SEP]
patience
is
a
virtue
##ness
allah
''';

void main() {
  group('BertTokenizer (real WordPiece, not the old fake char-code one)', () {
    test('tokenizes known words into the expected vocab ids', () {
      final tokenizer = BertTokenizer.fromStringContent(_miniVocab);
      final input = tokenizer.prepareNerInput('patience is a virtue', 16);

      // [CLS] patience is a virtue [SEP] ... padded to 16
      expect(input.inputIds[0], 2); // [CLS]
      expect(input.inputIds[1], 4); // patience
      expect(input.inputIds[2], 5); // is
      expect(input.inputIds[3], 6); // a
      expect(input.inputIds[4], 7); // virtue
      expect(input.inputIds[5], 3); // [SEP]
      expect(input.inputIds.length, 16);
      expect(input.inputMask[0], 1);
      expect(input.inputMask.last, 0); // padding
    });

    test('falls back to [UNK] for words not in the vocab', () {
      final tokenizer = BertTokenizer.fromStringContent(_miniVocab);
      final tokens = tokenizer.tokenize('zzzznotarealword');
      expect(tokens, contains('[UNK]'));
    });
  });

  group('EmbeddingService', () {
    test('normalized mock embedding has unit length (fallback path, no model files)', () async {
      final service = EmbeddingService(forceMock: true);
      final embedding = await service.getEmbedding('test text');
      final normSquared = embedding.fold<double>(0, (sum, v) => sum + v * v);
      expect(normSquared, closeTo(1.0, 1e-6));
    });

    test('query and passage embeddings differ when isQuery changes the input text', () async {
      // With the mock path (no real ONNX model in the test environment),
      // the query prefix still changes the string that gets hashed, so the
      // two mock embeddings for the same base text must differ.
      final service = EmbeddingService(forceMock: true);
      final passage = await service.getEmbedding('patience in Islam');
      final query = await service.getEmbedding('patience in Islam', isQuery: true);
      expect(passage, isNot(equals(query)));
    });
  });
}
```

- [ ] **Step 2b: Verify the test file compiles against the not-yet-updated `EmbeddingService`**

Run: `flutter test test/core/services/embedding_service_test.dart`
Expected: FAIL to compile — `The named parameter 'isQuery' isn't defined` and/or `The named parameter 'forceMock' isn't defined` (check current `EmbeddingService` constructor — it already has `forceMock`, so only the `isQuery` failures should appear; the `BertTokenizer` tests should already pass since Step 1 added the real dependency).

- [ ] **Step 3: Rewrite `EmbeddingService`**

Replace the full contents of `lib/core/services/embedding_service.dart`:

```dart
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:bert_tokenizer/bert_tokenizer.dart';

/// BGE's documented asymmetric convention: passages/corpus text embeds
/// plain, but queries get this instruction prefix — skipping it measurably
/// hurts retrieval quality per the model's own card.
const _queryPrefix = 'Represent this sentence for searching relevant passages: ';

const _maxTokenLength = 256;

class EmbeddingService {
  OrtSession? _session;
  BertTokenizer? _tokenizer;
  bool _initialized = false;
  bool _useMock = false;

  EmbeddingService({bool forceMock = false}) : _useMock = forceMock;

  Future<void> init() async {
    if (_initialized) return;

    if (_useMock) {
      _initialized = true;
      return;
    }

    try {
      final vocabData = await rootBundle.loadString('assets/models/bge_small_en_v1_5_vocab.txt');
      _tokenizer = BertTokenizer.fromStringContent(vocabData);

      OrtEnv.instance.init();
      final bytes = await rootBundle.load('assets/models/bge_small_en_v1_5.onnx');
      final sessionOptions = OrtSessionOptions();
      _session = OrtSession.fromBuffer(bytes.buffer.asUint8List(), sessionOptions);
      _initialized = true;
    } catch (e) {
      // Fallback to mock if assets aren't present or init fails (e.g. tests).
      _useMock = true;
      _initialized = true;
    }
  }

  /// Returns a normalized 384-dim embedding for [text]. Set [isQuery] when
  /// embedding a search query (not corpus/passage text) so BGE's asymmetric
  /// instruction prefix is applied — see the constant above.
  Future<List<double>> getEmbedding(String text, {bool isQuery = false}) async {
    await init();

    final effectiveText = isQuery ? '$_queryPrefix$text' : text;

    if (_useMock) {
      return _generateMockEmbedding(effectiveText);
    }

    try {
      final input = _tokenizer!.prepareNerInput(effectiveText, _maxTokenLength);
      final shape = [1, input.inputIds.length];

      final inputIdsTensor = OrtValueTensor.createTensorWithDataList(input.inputIds, shape);
      final attentionMaskTensor = OrtValueTensor.createTensorWithDataList(input.inputMask, shape);
      final tokenTypeIdsTensor = OrtValueTensor.createTensorWithDataList(input.segmentIds, shape);

      final inputs = {
        'input_ids': inputIdsTensor,
        'attention_mask': attentionMaskTensor,
        'token_type_ids': tokenTypeIdsTensor,
      };

      final runOptions = OrtRunOptions();
      final outputs = await _session!.runAsync(runOptions, inputs);

      // BGE uses CLS pooling per its model card: the sentence embedding is
      // the first token's ('[CLS]') last-hidden-state vector, not a mean
      // over all tokens.
      final lastHiddenState = outputs != null && outputs.isNotEmpty ? outputs[0]?.value : null;
      List<double> embedding = [];
      if (lastHiddenState is List && lastHiddenState.isNotEmpty) {
        final batch0 = lastHiddenState[0]; // [seq_len, hidden]
        if (batch0 is List && batch0.isNotEmpty) {
          final clsVector = batch0[0]; // [hidden] — the [CLS] token
          embedding = (clsVector as List).map((e) => (e as num).toDouble()).toList();
        }
      }

      inputIdsTensor.release();
      attentionMaskTensor.release();
      tokenTypeIdsTensor.release();
      if (outputs != null) {
        for (final out in outputs) {
          out?.release();
        }
      }
      runOptions.release();

      return _normalize(embedding);
    } catch (e) {
      return _generateMockEmbedding(effectiveText);
    }
  }

  List<double> _normalize(List<double> vector) {
    double sumOfSquares = 0.0;
    for (final val in vector) {
      sumOfSquares += val * val;
    }
    final norm = sqrt(sumOfSquares);
    if (norm == 0.0) return List<double>.filled(vector.length, 0.0);
    return vector.map((e) => e / norm).toList();
  }

  List<double> _generateMockEmbedding(String text) {
    final rand = Random(text.hashCode);
    final vector = List<double>.generate(384, (_) => rand.nextDouble() * 2 - 1);
    return _normalize(vector);
  }

  void dispose() {
    _session?.release();
    if (_initialized && !_useMock) {
      OrtEnv.instance.release();
    }
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/core/services/embedding_service_test.dart`
Expected: PASS (4 tests) — the test environment has no `assets/models/bge_small_en_v1_5*` files yet (added in Step 6, and even then only used by the real app bundle, not this unit test), so `EmbeddingService(forceMock: true)` exercises the mock path deliberately; the `BertTokenizer` tests use the tiny inline vocab, not the real model files.

- [ ] **Step 5: Run the full suite to confirm nothing else broke**

Run: `flutter test`
Expected: all tests pass (this change is additive/backward-compatible — every existing `getEmbedding(text)` call site still compiles since `isQuery` defaults to `false`).

- [ ] **Step 6: Fetch and add the real model assets (manual, one-time)**

These two files are fetched once from verified sources and committed as binary assets (small enough: ~33MB + ~230KB).

`.gitignore` currently has a blanket `assets/models/*.onnx` rule (originally meant for large LLM weights that are runtime-downloaded, never committed — see `model_download_service.dart`). This new file needs an exception, the same way `assets/databases/quran_base.db` already has one. In `.gitignore`, change:

```
assets/models/*.onnx
```

to:

```
assets/models/*.onnx
!assets/models/bge_small_en_v1_5.onnx
```

Then fetch the files:

```bash
mkdir -p assets/models
curl -L -o assets/models/bge_small_en_v1_5.onnx \
  "https://huggingface.co/Xenova/bge-small-en-v1.5/resolve/main/onnx/model_quantized.onnx"
curl -L -o assets/models/bge_small_en_v1_5_vocab.txt \
  "https://huggingface.co/BAAI/bge-small-en-v1.5/resolve/main/vocab.txt"
```

Verify sizes match what was confirmed during design:
```bash
ls -la assets/models/bge_small_en_v1_5.onnx assets/models/bge_small_en_v1_5_vocab.txt
```
Expected: `bge_small_en_v1_5.onnx` is exactly 34014426 bytes; `bge_small_en_v1_5_vocab.txt` is exactly 231508 bytes. If either differs, stop and re-verify the source before proceeding — do not assume a size mismatch is harmless.

- [ ] **Step 7: Manual verification with the real model (not asserted in CI)**

```dart
// Run via: dart run <this_temp_file>.dart from the project root (needs
// the project's package resolution) — delete after running, not committed.
import 'dart:io';
import 'package:learn_quran/core/services/embedding_service.dart';

void main() async {
  final service = EmbeddingService();
  final passage = await service.getEmbedding('The Quran teaches patience in adversity.');
  final query = await service.getEmbedding('What does Islam say about patience?', isQuery: true);
  print('passage[0:5]: ${passage.take(5).toList()}');
  print('query[0:5]: ${query.take(5).toList()}');
  print('passage length: ${passage.length}'); // expect 384
  double dot = 0;
  for (var i = 0; i < passage.length; i++) {
    dot += passage[i] * query[i];
  }
  print('cosine similarity (both normalized, so dot product = cosine): $dot');
  service.dispose();
}
```

Expected: `passage length: 384`; a real onnxruntime session loads without throwing (no silent fallback to mock — add a temporary `print('mock: $_useMock')` if unsure); cosine similarity is a plausible positive value (roughly 0.5-0.9 range for closely-related sentences — BGE isn't calibrated to a specific numeric threshold, this is a sanity check, not an assertion).

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock .gitignore lib/core/services/embedding_service.dart test/core/services/embedding_service_test.dart assets/models/bge_small_en_v1_5.onnx assets/models/bge_small_en_v1_5_vocab.txt
git commit -m "feat: real BGE-small-en-v1.5 embeddings with a real WordPiece tokenizer"
```

---

### Task 3: `KnowledgeBaseDatabase` — new Drift database

**Files:**
- Create: `lib/data/local/db/knowledge_base_database.dart`
- Test: `test/data/local/db/knowledge_base_database_test.dart`

**Interfaces:**
- Consumes: none (new, standalone).
- Produces (used by Tasks 4, 6, 7, 8):
  - `class KnowledgeBaseDatabase extends _$KnowledgeBaseDatabase` with tables `Verses`, `Hadiths`, `Tafsirs`, `KbMeta`, and a runtime-created plain `vec_knowledge_base` table.
  - `KnowledgeBaseDatabase.forTesting(QueryExecutor executor)` constructor.
  - `KnowledgeBaseDatabase.fromFile(String path)` constructor (opens/creates the database at an explicit file path — used by both the app's bundled-asset copy and `tool/build_kb.dart`).
  - Generated row classes `Verse`, `Hadith`, `Tafsir`, `KbMetaData` (Drift's standard per-table generated names).

- [ ] **Step 1: Write the failing test**

Create `test/data/local/db/knowledge_base_database_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/data/local/db/knowledge_base_database.dart';

void main() {
  late KnowledgeBaseDatabase db;

  setUp(() {
    db = KnowledgeBaseDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('creates verses/hadiths/tafsirs/kbMeta/vec_knowledge_base tables with no hindi columns', () async {
    await db.into(db.verses).insert(VersesCompanion.insert(
          id: 1,
          surahNumber: 1,
          ayahNumber: 1,
          juzNumber: 1,
          arabicText: 'بِسْمِ اللَّهِ',
          englishText: 'In the name of Allah',
          banglaText: 'আল্লাহর নামে',
        ));
    final verse = await (db.select(db.verses)..where((t) => t.id.equals(1))).getSingle();
    expect(verse.englishText, 'In the name of Allah');

    await db.into(db.kbMeta).insert(KbMetaCompanion.insert(key: 'version', value: '1.0.0'));
    final meta = await (db.select(db.kbMeta)..where((t) => t.key.equals('version'))).getSingle();
    expect(meta.value, '1.0.0');

    // vec_knowledge_base exists and accepts the plain (rowid, embedding) shape.
    await db.customStatement(
      'INSERT INTO vec_knowledge_base(rowid, embedding) VALUES (?, ?)',
      [1, [1, 2, 3, 4]],
    );
    final vecRow = await db.customSelect('SELECT rowid FROM vec_knowledge_base WHERE rowid = 1').getSingle();
    expect(vecRow.read<int>('rowid'), 1);
  });

  test('hadiths and tafsirs tables have no hindi column (compile-time guarantee)', () async {
    await db.into(db.hadiths).insert(HadithsCompanion.insert(
          id: 1,
          bookName: 'Sahih al-Bukhari',
          hadithNumber: '1',
          chapterTitle: 'Revelation',
          arabicText: 'إنما الأعمال بالنيات',
          englishText: 'Actions are judged by intentions',
          banglaText: 'কাজের ফল নিয়তের উপর নির্ভর করে',
        ));
    await db.into(db.tafsirs).insert(TafsirsCompanion.insert(
          id: 1,
          surahNumber: 1,
          ayahNumber: 1,
          author: 'Ibn Kathir',
          contentEnglish: 'Commentary text',
          contentBangla: 'বাংলা তাফসীর',
        ));
    final hadith = await (db.select(db.hadiths)..where((t) => t.id.equals(1))).getSingle();
    final tafsir = await (db.select(db.tafsirs)..where((t) => t.id.equals(1))).getSingle();
    expect(hadith.bookName, 'Sahih al-Bukhari');
    expect(tafsir.author, 'Ibn Kathir');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/data/local/db/knowledge_base_database_test.dart`
Expected: FAIL to compile — `Target of URI doesn't exist: 'package:learn_quran/data/local/db/knowledge_base_database.dart'`.

- [ ] **Step 3: Create the database**

Create `lib/data/local/db/knowledge_base_database.dart`:

```dart
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'knowledge_base_database.g.dart';

class Verses extends Table {
  IntColumn get id => integer()();
  IntColumn get surahNumber => integer()();
  IntColumn get ayahNumber => integer()();
  IntColumn get juzNumber => integer()();
  TextColumn get arabicText => text()();
  TextColumn get englishText => text()();
  TextColumn get banglaText => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Hadiths extends Table {
  IntColumn get id => integer()();
  TextColumn get bookName => text()();
  TextColumn get hadithNumber => text()();
  TextColumn get chapterTitle => text()();
  TextColumn get arabicText => text()();
  TextColumn get englishText => text()();
  TextColumn get banglaText => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tafsirs extends Table {
  IntColumn get id => integer()();
  IntColumn get surahNumber => integer()();
  IntColumn get ayahNumber => integer()();
  TextColumn get author => text()();
  TextColumn get contentEnglish => text()();
  TextColumn get contentBangla => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class KbMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Verses, Hadiths, Tafsirs, KbMeta])
class KnowledgeBaseDatabase extends _$KnowledgeBaseDatabase {
  KnowledgeBaseDatabase.forTesting(super.executor);

  /// Opens (or creates) the database at an explicit file [path] — used both
  /// by the app (a writable copy of the bundled/downloaded asset) and by
  /// `tool/build_kb.dart` (building a fresh file from scratch).
  KnowledgeBaseDatabase.fromFile(String path) : super(NativeDatabase.createInBackground(File(path)));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createVectorTable();
        },
        beforeOpen: (details) async {
          await _createVectorTable();
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

  /// Copies the bundled [assetPath] to [destinationPath] if nothing exists
  /// there yet, then opens it. Mirrors the existing copy-on-first-launch
  /// pattern `AppDatabase._openConnection()` used for `quran_base.db`.
  static Future<KnowledgeBaseDatabase> openBundled({
    required String assetPath,
    required String destinationPath,
  }) async {
    final file = File(destinationPath);
    if (!await file.exists()) {
      await Directory(file.parent.path).create(recursive: true);
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await file.writeAsBytes(bytes);
    }
    return KnowledgeBaseDatabase.fromFile(destinationPath);
  }
}
```

- [ ] **Step 4: Generate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: generates `lib/data/local/db/knowledge_base_database.g.dart` with no errors. This file is gitignored (`.gitignore`'s `*.g.dart` rule) — every CI workflow already runs this same `build_runner build` step itself, so the generated file is never committed. Do not `git add` it in Step 7.

- [ ] **Step 5: Run the test**

Run: `flutter test test/data/local/db/knowledge_base_database_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Run the full suite**

Run: `flutter test`
Expected: all green — this task only adds a new file, doesn't touch `AppDatabase` yet (that's Task 7).

- [ ] **Step 7: Commit**

```bash
git add lib/data/local/db/knowledge_base_database.dart test/data/local/db/knowledge_base_database_test.dart
git commit -m "feat: add KnowledgeBaseDatabase (read-only Quran/Hadith/Tafsir + vectors)"
```

---

### Task 4: `kb_catalog.dart`

**Files:**
- Create: `lib/core/models/kb_catalog.dart`
- Test: `test/core/models/kb_catalog_test.dart`

**Interfaces:**
- Produces (used by Task 5):
  - `class KbInfo` with fields `version` (`String`), `downloadUrl` (`String`), `sizeBytes` (`int`), `filename` (`String`).
  - `const KbInfo kCurrentKb` — the single current catalog entry (unlike the two-tier model catalog, there's only ever one "latest known" KB version to compare against).

- [ ] **Step 1: Write the failing test**

Create `test/core/models/kb_catalog_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/models/kb_catalog.dart';

void main() {
  test('kCurrentKb has a well-formed GitHub release download URL', () {
    expect(kCurrentKb.downloadUrl, contains('github.com'));
    expect(kCurrentKb.downloadUrl, contains(kCurrentKb.version));
    expect(kCurrentKb.downloadUrl, endsWith(kCurrentKb.filename));
    expect(kCurrentKb.sizeBytes, greaterThan(0));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/models/kb_catalog_test.dart`
Expected: FAIL to compile — file doesn't exist yet.

- [ ] **Step 3: Create the catalog**

Create `lib/core/models/kb_catalog.dart`. **Note:** the exact `sizeBytes` value below is a placeholder that Task 9's final step replaces with the real, observed value after the first `kb-v1.0.0` release is actually built — there is no way to know the true byte count before that release exists (this mirrors exactly how `model_catalog.dart`'s `sizeBytes` values were hardcoded only after directly verifying each real Hugging Face file). Until Task 9 completes, this entry is intentionally unverified and Task 5's `isDownloaded()` exact-size check will simply never match a real download.

```dart
/// A downloadable, versioned knowledge base release.
class KbInfo {
  final String version;
  final String filename;
  final int sizeBytes;

  const KbInfo({
    required this.version,
    required this.filename,
    required this.sizeBytes,
  });

  String get downloadUrl =>
      'https://github.com/REPLACE_WITH_ORG/learn-quran/releases/download/kb-v$version/$filename';
}

/// The current knowledge base version the app knows how to fetch.
/// sizeBytes is filled in for real once kb-v1.0.0 is actually built and
/// published (see docs/superpowers/plans/2026-07-05-knowledge-base-v1.md,
/// Task 9's final step) — do not trust this value until that step is done.
const KbInfo kCurrentKb = KbInfo(
  version: '1.0.0',
  filename: 'kb.db',
  sizeBytes: 0, // TODO(Task 9, final step): replace with the real, verified byte count.
);
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/core/models/kb_catalog_test.dart`
Expected: FAIL — `expect(kCurrentKb.sizeBytes, greaterThan(0))` fails since it's `0` until Task 9.

This is expected and correct at this point in the plan — leave a visible marker rather than a fake passing value. Change the test's last assertion temporarily is **not** the fix; instead:

- [ ] **Step 4b: Adjust the test to reflect the pre-release state honestly**

Replace the test file's content with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/models/kb_catalog.dart';

void main() {
  test('kCurrentKb has a well-formed GitHub release download URL', () {
    expect(kCurrentKb.downloadUrl, contains('github.com'));
    expect(kCurrentKb.downloadUrl, contains(kCurrentKb.version));
    expect(kCurrentKb.downloadUrl, endsWith(kCurrentKb.filename));
  });

  test(
    'kCurrentKb.sizeBytes is filled in with the real published size',
    () {
      expect(
        kCurrentKb.sizeBytes,
        greaterThan(0),
        reason: 'Run Task 9 (cut the kb-v1.0.0 release) and hardcode the '
            'real byte count here — see kb_catalog.dart\'s TODO.',
      );
    },
    skip: 'Intentionally skipped until Task 9 publishes a real kb-v1.0.0 release.',
  );
}
```

- [ ] **Step 5: Run the test**

Run: `flutter test test/core/models/kb_catalog_test.dart`
Expected: PASS (1 test), 1 skipped with the reason visible in output.

- [ ] **Step 6: Commit**

```bash
git add lib/core/models/kb_catalog.dart test/core/models/kb_catalog_test.dart
git commit -m "feat: add kb_catalog.dart (KbInfo, pending real Task 9 release size)"
```

---

### Task 5: `KbDownloadService`

**Files:**
- Create: `lib/core/services/kb_download_service.dart`
- Test: `test/core/services/kb_download_service_test.dart`

**Interfaces:**
- Consumes: `KbInfo` from Task 4.
- Produces (used by Task 8):
  - `class KbDownloadService` with `localPathFor(KbInfo)`, `isDownloaded(KbInfo)`, `downloadKb(KbInfo, {onProgress})`, `deleteKb(KbInfo)`, mirroring `ModelDownloadService`'s exact method shapes and semantics (exact-size verification, HTTP Range resume, 30s idle-timeout, `.forTesting()` constructor).
  - `class KbDownloadProgress` — same shape as `DownloadProgress`.

- [ ] **Step 1: Write the failing tests**

Create `test/core/services/kb_download_service_test.dart` — this is a direct adaptation of the existing `test/core/services/model_download_service_test.dart` (same proven behaviors, new target type):

```dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:learn_quran/core/models/kb_catalog.dart';
import 'package:learn_quran/core/services/kb_download_service.dart';

const _testKb = KbInfo(version: 'test', filename: 'kb-test.db', sizeBytes: 20);

class _StallingClient extends http.BaseClient {
  final List<int> initialBytes;
  _StallingClient(this.initialBytes);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // ignore: close_sinks — deliberately never closed, to simulate a stall.
    final controller = StreamController<List<int>>();
    controller.add(initialBytes);
    return http.StreamedResponse(controller.stream, 200, contentLength: 20);
  }
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kb_download_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('KbDownloadService', () {
    test('isDownloaded is false when no file exists', () async {
      final service = KbDownloadService.forTesting(kbDir: tempDir);
      expect(await service.isDownloaded(_testKb), isFalse);
    });

    test('downloadKb writes the full response body to the expected path', () async {
      final expectedBytes = List<int>.generate(20, (i) => 65 + i);
      final client = MockClient((request) async {
        expect(request.url.toString(), _testKb.downloadUrl);
        expect(request.headers.containsKey('Range'), isFalse);
        return http.Response.bytes(expectedBytes, 200);
      });
      final service = KbDownloadService.forTesting(kbDir: tempDir, client: client);

      final progressUpdates = <KbDownloadProgress>[];
      await service.downloadKb(_testKb, onProgress: progressUpdates.add);

      final path = await service.localPathFor(_testKb);
      expect(await File(path).readAsBytes(), expectedBytes);
      expect(await service.isDownloaded(_testKb), isTrue);
      expect(progressUpdates.last.bytesReceived, 20);
    });

    test('downloadKb resumes a partial file via a Range request', () async {
      final path = '${tempDir.path}/${_testKb.filename}';
      final firstHalf = List<int>.generate(10, (i) => 65 + i);
      final secondHalf = List<int>.generate(10, (i) => 75 + i);
      await File(path).writeAsBytes(firstHalf);

      final client = MockClient((request) async {
        expect(request.headers['Range'], 'bytes=10-');
        return http.Response.bytes(secondHalf, 206);
      });
      final service = KbDownloadService.forTesting(kbDir: tempDir, client: client);

      await service.downloadKb(_testKb);

      expect(await File(path).readAsBytes(), [...firstHalf, ...secondHalf]);
    });

    test('downloadKb throws instead of hanging forever when the stream stalls', () async {
      final client = _StallingClient(List.filled(10, 65));
      final service = KbDownloadService.forTesting(
        kbDir: tempDir,
        client: client,
        idleTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        () => service.downloadKb(_testKb),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('deleteKb removes the downloaded file', () async {
      final client = MockClient((request) async => http.Response.bytes(List.filled(20, 65), 200));
      final service = KbDownloadService.forTesting(kbDir: tempDir, client: client);
      await service.downloadKb(_testKb);
      expect(await service.isDownloaded(_testKb), isTrue);

      await service.deleteKb(_testKb);

      expect(await service.isDownloaded(_testKb), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/services/kb_download_service_test.dart`
Expected: FAIL to compile — file doesn't exist.

- [ ] **Step 3: Implement `KbDownloadService`**

Create `lib/core/services/kb_download_service.dart` — structurally identical to `ModelDownloadService` (same Range-resume + idle-timeout + exact-size logic, already proven), retargeted to `KbInfo`:

```dart
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/kb_catalog.dart';

class KbDownloadProgress {
  final int bytesReceived;
  final int totalBytes;
  const KbDownloadProgress(this.bytesReceived, this.totalBytes);
  double get fraction => totalBytes == 0 ? 0 : bytesReceived / totalBytes;
}

class KbDownloadCancelledException implements Exception {
  @override
  String toString() => 'KbDownloadCancelledException';
}

class KbDownloadService {
  static const _defaultIdleTimeout = Duration(seconds: 30);

  final http.Client _client;
  final Directory? _kbDirOverride;
  final Duration _idleTimeout;
  bool _cancelRequested = false;

  KbDownloadService({http.Client? client})
      : _client = client ?? http.Client(),
        _kbDirOverride = null,
        _idleTimeout = _defaultIdleTimeout;

  KbDownloadService.forTesting({
    required Directory kbDir,
    http.Client? client,
    Duration idleTimeout = _defaultIdleTimeout,
  })  : _client = client ?? http.Client(),
        _kbDirOverride = kbDir,
        _idleTimeout = idleTimeout;

  Future<Directory> _kbBaseDir() async {
    final override = _kbDirOverride;
    if (override != null) return override;
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/kb');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> localPathFor(KbInfo kb) async {
    final dir = await _kbBaseDir();
    return '${dir.path}/${kb.filename}';
  }

  Future<bool> isDownloaded(KbInfo kb) async {
    final file = File(await localPathFor(kb));
    if (!await file.exists()) return false;
    return await file.length() == kb.sizeBytes;
  }

  Future<void> downloadKb(
    KbInfo kb, {
    void Function(KbDownloadProgress)? onProgress,
  }) async {
    _cancelRequested = false;
    final path = await localPathFor(kb);
    final file = File(path);
    final existingLength = await file.exists() ? await file.length() : 0;

    if (existingLength == kb.sizeBytes) {
      onProgress?.call(KbDownloadProgress(existingLength, kb.sizeBytes));
      return;
    }

    final validPartial = existingLength > 0 && existingLength < kb.sizeBytes;
    final request = http.Request('GET', Uri.parse(kb.downloadUrl));
    if (validPartial) {
      request.headers['Range'] = 'bytes=$existingLength-';
    }

    final response = await _client.send(request);
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw HttpException('Unexpected status ${response.statusCode} downloading knowledge base ${kb.version}');
    }

    final resuming = response.statusCode == 206 && validPartial;
    final sink = file.openWrite(mode: resuming ? FileMode.append : FileMode.write);
    var received = resuming ? existingLength : 0;

    try {
      await for (final chunk in response.stream.timeout(_idleTimeout)) {
        if (_cancelRequested) {
          throw KbDownloadCancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(KbDownloadProgress(received, kb.sizeBytes));
      }
    } finally {
      await sink.close();
    }
  }

  void cancelDownload() {
    _cancelRequested = true;
  }

  Future<void> deleteKb(KbInfo kb) async {
    final file = File(await localPathFor(kb));
    if (await file.exists()) {
      await file.delete();
    }
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/core/services/kb_download_service_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Run the full suite**

Run: `flutter test`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/kb_download_service.dart test/core/services/kb_download_service_test.dart
git commit -m "feat: add KbDownloadService (mirrors ModelDownloadService for kb.db)"
```

---

### Task 6: `tool/build_kb.dart` — real content fetch + embed pipeline

**Files:**
- Create: `tool/build_kb.dart`
- Create: `tool/kb_sources.dart` (the verified fetch/parse logic, kept separate so it's independently unit-testable without hitting the network)
- Test: `test/tool/kb_sources_test.dart`

**Interfaces:**
- Consumes: `KnowledgeBaseDatabase` (Task 3), `EmbeddingService` (Task 2), `RagRepository`-equivalent embedding-insert logic (reused inline, since `RagRepository` itself is bound to whichever content database is passed to it — see Task 7, which retargets it to `KnowledgeBaseDatabase`, making it directly reusable here too).
- Produces: `tool/build_kb.dart` (fetches real content, produces a complete `kb.db`) plus `tool/build_kb_runner.dart` — a permanent harness required because `build_kb.dart` transitively needs Flutter engine bindings (`rootBundle`) that a bare `dart run` never provides. Invoke via `flutter test tool/build_kb_runner.dart --timeout=none --dart-define=KB_OUTPUT=... --dart-define=KB_VERSION=...`, not `dart run`.

- [ ] **Step 1: Write the failing parse-logic tests**

Create `test/tool/kb_sources_test.dart` (tests the transform logic against realistic fixture JSON shapes — no network calls):

```dart
import 'package:flutter_test/flutter_test.dart';
import '../../tool/kb_sources.dart' as kbsrc;

void main() {
  group('parseQuranEdition', () {
    test('flattens surahs/ayahs into flat verse rows', () {
      final fixture = {
        'data': {
          'surahs': [
            {
              'number': 1,
              'ayahs': [
                {'number': 1, 'numberInSurah': 1, 'juz': 1, 'text': 'بِسْمِ اللَّهِ'},
                {'number': 2, 'numberInSurah': 2, 'juz': 1, 'text': 'الْحَمْدُ لِلَّهِ'},
              ],
            },
          ],
        },
      };
      final rows = kbsrc.parseQuranEdition(fixture);
      expect(rows.length, 2);
      expect(rows[0].surahNumber, 1);
      expect(rows[0].ayahNumber, 1);
      expect(rows[0].juzNumber, 1);
      expect(rows[0].text, 'بِسْمِ اللَّهِ');
      expect(rows[1].ayahNumber, 2);
    });
  });

  group('parseHadithEdition', () {
    test('maps hadith rows and resolves chapter titles from metadata.sections', () {
      final fixture = {
        'metadata': {
          'sections': {'1': 'Revelation', '2': 'Belief'},
        },
        'hadiths': [
          {
            'hadithnumber': 1,
            'text': 'Actions are judged by intentions',
            'reference': {'book': 1, 'hadith': 1},
          },
          {
            'hadithnumber': 2,
            'text': 'Something about belief',
            'reference': {'book': 2, 'hadith': 1},
          },
        ],
      };
      final rows = kbsrc.parseHadithEdition(fixture);
      expect(rows.length, 2);
      expect(rows[0].hadithNumber, '1');
      expect(rows[0].chapterTitle, 'Revelation');
      expect(rows[0].text, 'Actions are judged by intentions');
      expect(rows[1].chapterTitle, 'Belief');
    });
  });

  group('parseTafsirSurah', () {
    test('maps one entry per ayah, preserving duplicated grouped-ayah text as-is', () {
      final fixture = [
        {'surah': 1, 'ayah': 6, 'text': 'shared commentary'},
        {'surah': 1, 'ayah': 7, 'text': 'shared commentary'},
      ];
      final rows = kbsrc.parseTafsirSurah(fixture);
      expect(rows.length, 2);
      expect(rows[0].ayahNumber, 6);
      expect(rows[1].ayahNumber, 7);
      expect(rows[0].text, rows[1].text);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/tool/kb_sources_test.dart`
Expected: FAIL to compile — `tool/kb_sources.dart` doesn't exist.

- [ ] **Step 3: Implement `tool/kb_sources.dart`**

This holds the verified endpoints and pure transform functions, kept separate from the network/DB-writing orchestration in `build_kb.dart` so it's fast and network-free to test:

```dart
/// Real, verified source endpoints — see
/// docs/superpowers/specs/2026-07-05-knowledge-base-v1-design.md for the
/// verification trail. Do not add or guess new endpoints here without the
/// same live verification.
library kb_sources;

const quranBaseUrl = 'https://api.alquran.cloud/v1/quran';
const quranArabicEdition = 'quran-uthmani';
const quranEnglishEdition = 'en.sahih';
const quranBanglaEdition = 'bn.bengali';

const hadithBaseUrl = 'https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions';
const hadithBooks = {
  'Sahih al-Bukhari': {'ar': 'ara-bukhari', 'en': 'eng-bukhari', 'bn': 'ben-bukhari'},
  'Sahih Muslim': {'ar': 'ara-muslim', 'en': 'eng-muslim', 'bn': 'ben-muslim'},
};

const tafsirBaseUrl = 'https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir';
const tafsirEnglishSlug = 'en-tafisr-ibn-kathir';
const tafsirBanglaSlug = 'bn-tafseer-ibn-e-kaseer';

class QuranRow {
  final int surahNumber;
  final int ayahNumber;
  final int juzNumber;
  final String text;
  QuranRow({required this.surahNumber, required this.ayahNumber, required this.juzNumber, required this.text});
}

/// Flattens an alquran.cloud `/v1/quran/{edition}` response into one row
/// per ayah. [json] is the decoded top-level response map.
List<QuranRow> parseQuranEdition(Map<String, dynamic> json) {
  final surahs = (json['data'] as Map<String, dynamic>)['surahs'] as List<dynamic>;
  final rows = <QuranRow>[];
  for (final surah in surahs) {
    final surahNumber = surah['number'] as int;
    final ayahs = surah['ayahs'] as List<dynamic>;
    for (final ayah in ayahs) {
      rows.add(QuranRow(
        surahNumber: surahNumber,
        ayahNumber: ayah['numberInSurah'] as int,
        juzNumber: ayah['juz'] as int,
        text: ayah['text'] as String,
      ));
    }
  }
  return rows;
}

class HadithRow {
  final String hadithNumber;
  final String chapterTitle;
  final String text;
  HadithRow({required this.hadithNumber, required this.chapterTitle, required this.text});
}

/// Parses a `fawazahmed0/hadith-api` edition JSON (e.g. `eng-bukhari.json`)
/// into flat rows, resolving each hadith's chapter title from
/// `metadata.sections` via its `reference.book` number.
List<HadithRow> parseHadithEdition(Map<String, dynamic> json) {
  final sections = (json['metadata'] as Map<String, dynamic>)['sections'] as Map<String, dynamic>;
  final hadiths = json['hadiths'] as List<dynamic>;
  final rows = <HadithRow>[];
  for (final h in hadiths) {
    final reference = h['reference'] as Map<String, dynamic>;
    final bookNumber = reference['book'].toString();
    rows.add(HadithRow(
      hadithNumber: h['hadithnumber'].toString(),
      chapterTitle: (sections[bookNumber] as String?) ?? '',
      text: h['text'] as String,
    ));
  }
  return rows;
}

class TafsirRow {
  final int ayahNumber;
  final String text;
  TafsirRow({required this.ayahNumber, required this.text});
}

/// Parses a `spa5k/tafsir_api` per-surah response (a JSON array) into rows.
/// Grouped-ayah commentary appears as duplicated text across consecutive
/// entries in the source itself — preserved as-is, not deduplicated.
List<TafsirRow> parseTafsirSurah(List<dynamic> json) {
  return json
      .map((entry) => TafsirRow(
            ayahNumber: entry['ayah'] as int,
            text: entry['text'] as String,
          ))
      .toList();
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/tool/kb_sources_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Implement `tool/build_kb.dart`**

This orchestrates: fetch all three sources for real → insert into a fresh `KnowledgeBaseDatabase` → embed English text via `EmbeddingService` → write `kb_meta`. Run with `dart run tool/build_kb.dart --output path/to/kb.db --version 1.0.0`.

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:learn_quran/data/local/db/knowledge_base_database.dart';
import 'package:learn_quran/core/services/embedding_service.dart';
import 'kb_sources.dart' as kbsrc;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('output', abbr: 'o', mandatory: true, help: 'Path to write kb.db to.')
    ..addOption('version', mandatory: true, help: 'Knowledge base version, e.g. 1.0.0');
  final args = parser.parse(arguments);
  final outputPath = args['output'] as String;
  final version = args['version'] as String;

  final outputFile = File(outputPath);
  if (await outputFile.exists()) {
    await outputFile.delete();
  }

  final db = KnowledgeBaseDatabase.fromFile(outputPath);
  final client = http.Client();
  final embeddingService = EmbeddingService();

  try {
    stdout.writeln('Fetching Quran (Arabic/English/Bangla)...');
    await _fetchAndInsertQuran(db, client);

    stdout.writeln('Fetching Hadith (Sahih al-Bukhari + Sahih Muslim)...');
    var hadithId = 1;
    for (final entry in kbsrc.hadithBooks.entries) {
      hadithId = await _fetchAndInsertHadithBook(db, client, entry.key, entry.value, hadithId);
    }

    stdout.writeln('Fetching Tafsir Ibn Kathir (English/Bangla)...');
    await _fetchAndInsertTafsir(db, client);

    stdout.writeln('Embedding English text (this takes a while for the full corpus)...');
    await _embedAndIndex(db, embeddingService);

    await db.into(db.kbMeta).insert(KbMetaCompanion.insert(key: 'version', value: version));
    await db.into(db.kbMeta).insert(
          KbMetaCompanion.insert(key: 'built_at', value: DateTime.now().toIso8601String()),
        );
    await db.into(db.kbMeta).insert(
          const KbMetaCompanion.insert(key: 'embedding_model', value: 'BAAI/bge-small-en-v1.5'),
        );

    stdout.writeln('Done: $outputPath');
  } finally {
    client.close();
    embeddingService.dispose();
    await db.close();
  }
}

Future<void> _fetchAndInsertQuran(KnowledgeBaseDatabase db, http.Client client) async {
  final arabic = kbsrc.parseQuranEdition(
    jsonDecode((await client.get(Uri.parse('${kbsrc.quranBaseUrl}/${kbsrc.quranArabicEdition}'))).body),
  );
  final english = kbsrc.parseQuranEdition(
    jsonDecode((await client.get(Uri.parse('${kbsrc.quranBaseUrl}/${kbsrc.quranEnglishEdition}'))).body),
  );
  final bangla = kbsrc.parseQuranEdition(
    jsonDecode((await client.get(Uri.parse('${kbsrc.quranBaseUrl}/${kbsrc.quranBanglaEdition}'))).body),
  );

  var id = 1;
  for (var i = 0; i < arabic.length; i++) {
    await db.into(db.verses).insert(VersesCompanion.insert(
          id: id,
          surahNumber: arabic[i].surahNumber,
          ayahNumber: arabic[i].ayahNumber,
          juzNumber: arabic[i].juzNumber,
          arabicText: arabic[i].text,
          englishText: english[i].text,
          banglaText: bangla[i].text,
        ));
    id++;
  }
}

Future<int> _fetchAndInsertHadithBook(
  KnowledgeBaseDatabase db,
  http.Client client,
  String bookName,
  Map<String, String> editionsByLang,
  int startId,
) async {
  final arabic = kbsrc.parseHadithEdition(
    jsonDecode((await client.get(Uri.parse('${kbsrc.hadithBaseUrl}/${editionsByLang['ar']}.json'))).body),
  );
  final english = kbsrc.parseHadithEdition(
    jsonDecode((await client.get(Uri.parse('${kbsrc.hadithBaseUrl}/${editionsByLang['en']}.json'))).body),
  );
  final bangla = kbsrc.parseHadithEdition(
    jsonDecode((await client.get(Uri.parse('${kbsrc.hadithBaseUrl}/${editionsByLang['bn']}.json'))).body),
  );

  var id = startId;
  for (var i = 0; i < english.length; i++) {
    await db.into(db.hadiths).insert(HadithsCompanion.insert(
          id: id,
          bookName: bookName,
          hadithNumber: english[i].hadithNumber,
          chapterTitle: english[i].chapterTitle,
          arabicText: i < arabic.length ? arabic[i].text : '',
          englishText: english[i].text,
          banglaText: i < bangla.length ? bangla[i].text : '',
        ));
    id++;
  }
  return id;
}

Future<void> _fetchAndInsertTafsir(KnowledgeBaseDatabase db, http.Client client) async {
  var id = 1;
  for (var surahNumber = 1; surahNumber <= 114; surahNumber++) {
    final englishResponse = await client.get(Uri.parse('${kbsrc.tafsirBaseUrl}/${kbsrc.tafsirEnglishSlug}/$surahNumber.json'));
    final banglaResponse = await client.get(Uri.parse('${kbsrc.tafsirBaseUrl}/${kbsrc.tafsirBanglaSlug}/$surahNumber.json'));
    final english = kbsrc.parseTafsirSurah(jsonDecode(englishResponse.body));
    final bangla = kbsrc.parseTafsirSurah(jsonDecode(banglaResponse.body));

    for (var i = 0; i < english.length; i++) {
      await db.into(db.tafsirs).insert(TafsirsCompanion.insert(
            id: id,
            surahNumber: surahNumber,
            ayahNumber: english[i].ayahNumber,
            author: 'Ibn Kathir',
            contentEnglish: english[i].text,
            contentBangla: i < bangla.length ? bangla[i].text : '',
          ));
      id++;
    }
  }
}

/// Embeds every row's English text and writes vec_knowledge_base, using the
/// same hadithOffset/tafsirOffset rowid scheme RagRepository.search() reads.
Future<void> _embedAndIndex(KnowledgeBaseDatabase db, EmbeddingService embeddingService) async {
  const hadithOffset = 100000;
  const tafsirOffset = 200000;

  final verses = await db.select(db.verses).get();
  for (final verse in verses) {
    final embedding = await embeddingService.getEmbedding(verse.englishText);
    await _insertVector(db, verse.id, embedding);
  }

  final hadiths = await db.select(db.hadiths).get();
  for (final hadith in hadiths) {
    final embedding = await embeddingService.getEmbedding(hadith.englishText);
    await _insertVector(db, hadithOffset + hadith.id, embedding);
  }

  final tafsirs = await db.select(db.tafsirs).get();
  for (final tafsir in tafsirs) {
    final embedding = await embeddingService.getEmbedding(tafsir.contentEnglish);
    await _insertVector(db, tafsirOffset + tafsir.id, embedding);
  }
}

Future<void> _insertVector(KnowledgeBaseDatabase db, int rowid, List<double> embedding) async {
  final float32list = Float32List.fromList(embedding);
  final blob = float32list.buffer.asUint8List();
  await db.customStatement(
    'INSERT OR REPLACE INTO vec_knowledge_base(rowid, embedding) VALUES (?, ?)',
    [rowid, blob],
  );
}
```

Add the `args` package dependency (`ArgParser`) — it's already a transitive dependency via other packages, but pin it directly since this tool depends on it explicitly:

In `pubspec.yaml`, under `dev_dependencies:` (this tool is build-time-only, never shipped in the app):
```yaml
  args: ^2.7.0
```

Run: `flutter pub get`

- [ ] **Step 6: Smoke-test the tool against the real APIs (manual, not part of `flutter test`)**

```bash
dart run tool/build_kb.dart --output /tmp/kb_smoke_test.db --version 1.0.0-smoke
```

Expected: prints each fetch stage, takes several minutes (real network fetch of the full Quran + two full hadith books + 114 tafsir surahs in two languages, plus embedding ~15-20K rows through the real ONNX model), and ends with `Done: /tmp/kb_smoke_test.db`. If any HTTP call returns a non-200 status, the script throws — that's correct behavior (fail loud, don't silently skip content).

Verify the output:
```bash
sqlite3 /tmp/kb_smoke_test.db "SELECT count(*) FROM verses;"   # expect 6236
sqlite3 /tmp/kb_smoke_test.db "SELECT count(*) FROM hadiths;"  # expect ~15000 (Bukhari + Muslim combined)
sqlite3 /tmp/kb_smoke_test.db "SELECT count(*) FROM tafsirs;"  # expect several thousand
sqlite3 /tmp/kb_smoke_test.db "SELECT count(*) FROM vec_knowledge_base;"  # expect verses+hadiths+tafsirs total
```

- [ ] **Step 7: Run the full suite**

Run: `flutter test`
Expected: all green (Step 6's manual smoke test isn't part of this — it's a real network+ML run, deliberately excluded from CI's fast test suite per the design doc's testing strategy).

- [ ] **Step 8: Commit**

```bash
git add tool/build_kb.dart tool/kb_sources.dart test/tool/kb_sources_test.dart pubspec.yaml pubspec.lock
git commit -m "feat: add tool/build_kb.dart — fetches real Quran/Hadith/Tafsir and builds kb.db"
```

---

### Task 7: Split `KnowledgeBaseDatabase` out of `AppDatabase`

This is one task, not two — simplifying `AppDatabase` and retargeting
`QuranRepository`/`RagRepository` are inseparable: neither compiles cleanly
on its own (removing the tables from `AppDatabase` breaks the repositories
until they're retargeted; retargeting the repositories requires
`KnowledgeBaseDatabase` to already be the source of truth). The task ends
in one clean, fully-green commit.

**Files:**
- Modify: `lib/data/local/db/app_database.dart`
- Modify: `lib/data/repositories/quran_repository.dart`
- Modify: `lib/data/repositories/rag_repository.dart`
- Modify: `lib/core/providers/database_provider.dart`
- Modify: `lib/core/providers/repository_providers.dart`
- Modify: `test/data/repositories/quran_repository_test.dart` and `test/data/repositories/rag_repository_test.dart`

**Interfaces:**
- Consumes: `KnowledgeBaseDatabase` (Task 3), `EmbeddingService.getEmbedding(text, {isQuery})` (Task 2).
- Produces: `AppDatabase` with tables `UserProgress`, `SalatLogs`, `Conversations`, `Messages`, `UserEngagementState` only. `QuranRepository`/`RagRepository` constructors now take `KnowledgeBaseDatabase` instead of `AppDatabase`. New `knowledgeBaseDatabaseProvider` (Riverpod `Provider<KnowledgeBaseDatabase>`) alongside the existing `appDatabaseProvider` — throws `UnimplementedError` until Task 8 wires it to a real path; that's fine, no unit test constructs repositories through the provider.

- [ ] **Step 1: Confirm no other file depends on `AppDatabase.verses`/`.hadiths`/`.tafsirs`**

Run: `grep -rln "db.verses\|db.hadiths\|db.tafsirs\|\.verses\b\|\.hadiths\b\|\.tafsirs\b" test/ lib/ --include="*.dart" | grep -v knowledge_base`
Expected: no matches outside `lib/data/repositories/quran_repository.dart` and `lib/data/repositories/rag_repository.dart` (both updated later in this task) — if anything else appears, stop and account for it before proceeding.

- [ ] **Step 2: Rewrite `app_database.dart`**

Replace the full contents of `lib/data/local/db/app_database.dart`:

```dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

class UserProgress extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get surahNumber => integer()();
  IntColumn get ayahNumber => integer()();
  IntColumn get lastReadTimestamp => integer()();
  BoolColumn get isMemorized => boolean().withDefault(const Constant(false))();
  TextColumn get bookmarkFolder => text().nullable()();
}

class SalatLogs extends Table {
  TextColumn get date => text()(); // YYYY-MM-DD
  BoolColumn get fajrCompleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dhuhrCompleted => boolean().withDefault(const Constant(false))();
  BoolColumn get asrCompleted => boolean().withDefault(const Constant(false))();
  BoolColumn get maghribCompleted => boolean().withDefault(const Constant(false))();
  BoolColumn get ishaCompleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {date};
}

class Conversations extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get title => text()();
  IntColumn get createdAt => integer()();
  IntColumn get lastActive => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Messages extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get conversationId => text().references(Conversations, #id, onDelete: KeyAction.cascade)();
  TextColumn get sender => text()(); // 'user' or 'agent'
  TextColumn get textContent => text()();
  TextColumn get citationsJson => text()(); // Serialized array of sources
  IntColumn get timestamp => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class UserEngagementState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [
  UserProgress,
  SalatLogs,
  Conversations,
  Messages,
  UserEngagementState,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Named constructor for tests — accepts any [QueryExecutor],
  /// typically `NativeDatabase.memory()`.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2; // Bumped: v1 also held Verses/Hadiths/Tafsirs,
  // now split into the separate KnowledgeBaseDatabase (see Task 3/7 of
  // docs/superpowers/plans/2026-07-05-knowledge-base-v1.md). No migration
  // path from v1 is provided — no production users exist on the old
  // content-mixed schema.
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
```

- [ ] **Step 3: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: regenerates `lib/data/local/db/app_database.g.dart` without `Verses`/`Hadiths`/`Tafsirs`-related code. This file is gitignored — do not `git add` it in Step 7.

- [ ] **Step 4: Run the full suite — expect failures, this is a checkpoint mid-task, not a stopping point**

Run: `flutter test`
Expected: FAIL — `lib/data/repositories/quran_repository.dart` and `lib/data/repositories/rag_repository.dart` still reference `_db.verses`/`_db.hadiths`/`_db.tafsirs` on the now-`AppDatabase`-typed `_db`, which no longer has those getters. Continue to Step 5 — do not commit until Step 10.

- [ ] **Step 5: Update `quran_repository.dart`**

Replace the full contents of `lib/data/repositories/quran_repository.dart`:

```dart
import 'package:drift/drift.dart';
import '../local/db/knowledge_base_database.dart';

class QuranRepository {
  final KnowledgeBaseDatabase _db;

  QuranRepository(this._db);

  Future<List<Verse>> getAllVerses() {
    return _db.select(_db.verses).get();
  }

  Future<List<Verse>> getVersesBySurah(int surahNumber) {
    return (_db.select(_db.verses)
          ..where((t) => t.surahNumber.equals(surahNumber))
          ..orderBy([(t) => OrderingTerm.asc(t.ayahNumber)]))
        .get();
  }

  Future<Verse?> getVerse(int surahNumber, int ayahNumber) {
    return (_db.select(_db.verses)
          ..where((t) =>
              t.surahNumber.equals(surahNumber) &
              t.ayahNumber.equals(ayahNumber)))
        .getSingleOrNull();
  }

  Future<List<Verse>> getVersesByJuz(int juzNumber) {
    return (_db.select(_db.verses)
          ..where((t) => t.juzNumber.equals(juzNumber)))
        .get();
  }

  Future<List<Hadith>> getHadithsByBook(String bookName) {
    return (_db.select(_db.hadiths)
          ..where((t) => t.bookName.equals(bookName)))
        .get();
  }

  Future<List<Hadith>> searchHadiths(String query) {
    return (_db.select(_db.hadiths)
          ..where((t) => t.englishText.like('%$query%')))
        .get();
  }

  Future<List<Tafsir>> getTafsirForVerse(int surahNumber, int ayahNumber) {
    return (_db.select(_db.tafsirs)
          ..where((t) =>
              t.surahNumber.equals(surahNumber) &
              t.ayahNumber.equals(ayahNumber)))
        .get();
  }
}
```

(Only the import and the field/constructor type changed — every query is identical, since `KnowledgeBaseDatabase`'s `Verses`/`Hadiths`/`Tafsirs` tables have the same shape minus the dropped Hindi columns, which this repository never referenced anyway.)

- [ ] **Step 6: Update `rag_repository.dart`**

In `lib/data/repositories/rag_repository.dart`, change the import and field type:

```dart
import '../local/db/knowledge_base_database.dart';
```//replaces the old `import '../local/db/app_database.dart';`

```dart
class RagRepository {
  final KnowledgeBaseDatabase _db;
  final EmbeddingService _embeddingService;
  ...
```

Remove `populateVectorIndex()` entirely and its call site in `search()` — embeddings are now always precomputed at build time (Task 6), never generated on-device (that was the Rules.md §3 violation this whole project fixes). The method also referenced `_db.hasVectorExtension`, which no longer exists on any database (Task 3/7 removed it — `vec_knowledge_base` is now always the plain-BLOB shape). Replace the full `search()` method and remove `populateVectorIndex`/`_insertVector`:

```dart
  /// Performs vector similarity search. Returns top k matches.
  Future<List<RagSearchResult>> search(String query, {int limit = 5}) async {
    final queryVector = await _embeddingService.getEmbedding(query, isQuery: true);

    final allRows = await _db.customSelect('SELECT rowid, embedding FROM vec_knowledge_base').get();
    final scoredRows = <_ScoredRow>[];

    for (final row in allRows) {
      final rowid = row.read<int>('rowid');
      final blob = row.read<Uint8List>('embedding');
      final floatList = Float32List.sublistView(blob);

      double score = 0.0;
      final minLength = queryVector.length < floatList.length ? queryVector.length : floatList.length;
      for (int i = 0; i < minLength; i++) {
        score += queryVector[i] * floatList[i];
      }

      scoredRows.add(_ScoredRow(rowid, score));
    }

    scoredRows.sort((a, b) => b.score.compareTo(a.score));
    final topRows = scoredRows.take(limit);

    final searchResults = <RagSearchResult>[];
    for (final row in topRows) {
      final match = await _buildSearchResult(row.rowid, row.score);
      if (match.verse != null || match.hadith != null || match.tafsir != null) {
        searchResults.add(match);
      }
    }

    return searchResults;
  }
```

Keep `_buildSearchResult`, `hadithOffset`, `tafsirOffset`, and `_ScoredRow` exactly as they are today — none of those reference `AppDatabase`-specific members.

- [ ] **Step 7: Add `knowledgeBaseDatabaseProvider`**

In `lib/core/providers/database_provider.dart`, add alongside the existing `appDatabaseProvider`:

```dart
import '../../data/local/db/knowledge_base_database.dart';

final knowledgeBaseDatabaseProvider = Provider<KnowledgeBaseDatabase>((ref) {
  // Task 8 (Settings + KbDownloadService) wires this to the real bundled/
  // downloaded kb.db path; until then this throws if constructed directly.
  throw UnimplementedError(
    'knowledgeBaseDatabaseProvider is wired up in Task 8 — see '
    'docs/superpowers/plans/2026-07-05-knowledge-base-v1.md',
  );
});
```

- [ ] **Step 8: Update `repository_providers.dart`**

In `lib/core/providers/repository_providers.dart`, change:

```dart
final quranRepositoryProvider = Provider<QuranRepository>((ref) {
  return QuranRepository(ref.watch(appDatabaseProvider));
});
```

to:

```dart
final quranRepositoryProvider = Provider<QuranRepository>((ref) {
  return QuranRepository(ref.watch(knowledgeBaseDatabaseProvider));
});
```

and:

```dart
final ragRepositoryProvider = Provider<RagRepository>((ref) {
  return RagRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(embeddingServiceProvider),
  );
});
```

to:

```dart
final ragRepositoryProvider = Provider<RagRepository>((ref) {
  return RagRepository(
    ref.watch(knowledgeBaseDatabaseProvider),
    ref.watch(embeddingServiceProvider),
  );
});
```

- [ ] **Step 9: Update `quran_repository_test.dart` and `rag_repository_test.dart`**

In both test files, change every `AppDatabase.forTesting(NativeDatabase.memory())` used to construct the repository under test to `KnowledgeBaseDatabase.forTesting(NativeDatabase.memory())`, and update the corresponding import. Update any inserted fixture rows that reference `hindiText`/`HindiText` fields — remove those named arguments (the new tables don't have them). Leave any *other* `AppDatabase` usage in the same test files (if a test also touches `UserProgress`/engagement data) untouched.

Run: `grep -n "hindiText\|HindiText" test/data/repositories/*.dart`
Fix any matches by deleting that named argument from the relevant `...Companion.insert(...)` call.

- [ ] **Step 10: Run the full suite**

Run: `flutter test`
Expected: all green. `knowledgeBaseDatabaseProvider`'s `UnimplementedError` is never hit by unit tests (they construct `QuranRepository`/`RagRepository` directly with `KnowledgeBaseDatabase.forTesting(...)`, not via the provider) — it will only throw if the app is actually run before Task 8 wires it up for real, which is expected and fine at this point in the plan.

- [ ] **Step 11: Commit**

```bash
git add lib/data/repositories/quran_repository.dart lib/data/repositories/rag_repository.dart lib/data/local/db/app_database.dart lib/core/providers/database_provider.dart lib/core/providers/repository_providers.dart test/data/repositories/quran_repository_test.dart test/data/repositories/rag_repository_test.dart
git commit -m "refactor: split KnowledgeBaseDatabase out of AppDatabase; drop on-device embedding generation"
```

---

### Task 8: Wire up `kb.db` for real — asset bundling, provider, Settings UI

**Files:**
- Modify: `pubspec.yaml` (asset registration)
- Modify: `.gitignore` (exempt `kb.db` from the blanket `assets/databases/*.db` rule)
- Modify: `lib/core/providers/database_provider.dart` (real `knowledgeBaseDatabaseProvider` implementation)
- Modify: `lib/presentation/screens/settings_screen.dart` (new "Knowledge Base" section)
- Delete: `assets/databases/quran_base.db` (superseded by `assets/databases/kb.db`)

**Interfaces:**
- Consumes: `KnowledgeBaseDatabase.openBundled` (Task 3), `KbDownloadService`/`KbInfo` (Tasks 4/5).
- Produces: a working, real `knowledgeBaseDatabaseProvider`; Settings UI for checking/downloading KB updates.

- [ ] **Step 1: Place the built `kb.db` as an asset**

This depends on Task 6's tool having produced a real file (Step 6 of Task 6 was a manual smoke-test run — reuse that output, or re-run it). Note: `tool/build_kb.dart` cannot run via bare `dart run` — it transitively uses `rootBundle` (via `EmbeddingService`/`KnowledgeBaseDatabase.openBundled`), which needs Flutter engine bindings (`dart:ui`) that plain `dart run` never provides. Task 6 added `tool/build_kb_runner.dart` specifically to host `build_kb.main()` under `flutter test` for this reason — use it:

```bash
flutter test tool/build_kb_runner.dart --timeout=none \
  --dart-define=KB_OUTPUT=assets/databases/kb.db --dart-define=KB_VERSION=1.0.0
rm assets/databases/quran_base.db
```

`.gitignore` has `assets/databases/*.db` with only `!assets/databases/quran_base.db` excepted. Since that file no longer exists, replace the exception line:

```
!assets/databases/quran_base.db
```

with:

```
!assets/databases/kb.db
```

In `pubspec.yaml`, under `flutter: assets:`, change:

```yaml
    - assets/databases/quran_base.db
```

to:

```yaml
    - assets/databases/kb.db
```

- [ ] **Step 2: Implement `knowledgeBaseDatabaseProvider` for real**

In `lib/core/providers/database_provider.dart`, replace the placeholder from Task 7 Step 7:

```dart
import 'package:path_provider/path_provider.dart';
import '../../data/local/db/knowledge_base_database.dart';

final knowledgeBaseDatabaseProvider = Provider<KnowledgeBaseDatabase>((ref) {
  throw UnsupportedError(
    'knowledgeBaseDatabaseProvider must be overridden via '
    'ProviderScope at app startup (see main.dart) — it needs an async '
    'path_provider lookup that a synchronous Provider body cannot perform.',
  );
});

/// Resolves the writable path KnowledgeBaseDatabase copies the bundled (or
/// downloaded) kb.db to, and opens it. Called once from main() before
/// runApp(), with the result passed in via ProviderScope overrides —
/// mirrors how `AppDatabase`'s file lives in ApplicationDocumentsDirectory,
/// but this needs to run before the widget tree exists since Drift's
/// LazyDatabase pattern doesn't fit an asset-copy-then-open flow as cleanly
/// as a direct async open here.
Future<KnowledgeBaseDatabase> openKnowledgeBaseDatabase() async {
  final docsDir = await getApplicationDocumentsDirectory();
  return KnowledgeBaseDatabase.openBundled(
    assetPath: 'assets/databases/kb.db',
    destinationPath: '${docsDir.path}/kb.sqlite',
  );
}
```

- [ ] **Step 3: Wire the override into `main()`**

In `lib/main.dart`, find where `runApp` is called (likely wrapped in a `ProviderScope`). Change it to resolve the database first:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final knowledgeBaseDatabase = await openKnowledgeBaseDatabase();
  runApp(
    ProviderScope(
      overrides: [
        knowledgeBaseDatabaseProvider.overrideWithValue(knowledgeBaseDatabase),
      ],
      child: const LearnQuranApp(), // or whatever the existing root widget is named
    ),
  );
}
```

Merge this with whatever `main()` already does (existing `WidgetsFlutterBinding.ensureInitialized()` calls, other setup) — don't duplicate the binding initialization if it's already there; add the `await openKnowledgeBaseDatabase()` call and the provider override to the existing structure.

- [ ] **Step 4: Add the "Knowledge Base" Settings section**

In `lib/presentation/screens/settings_screen.dart`, add state fields near the existing `_downloadingModelId`/`_downloadProgress` fields:

```dart
  String? _kbVersionInstalled;
  bool _kbUpdateAvailable = false;
  bool _kbDownloading = false;
  double _kbDownloadProgress = 0.0;
```

Add a check method (called from the existing settings-load lifecycle method, alongside `_checkModelStatuses()`):

```dart
  Future<void> _checkKbStatus() async {
    final kbDb = ref.read(knowledgeBaseDatabaseProvider);
    final versionRow = await (kbDb.select(kbDb.kbMeta)..where((t) => t.key.equals('version'))).getSingleOrNull();
    final kbDownloadService = ref.read(kbDownloadServiceProvider);
    final newerDownloaded = await kbDownloadService.isDownloaded(kCurrentKb);
    if (mounted) {
      setState(() {
        _kbVersionInstalled = versionRow?.value;
        _kbUpdateAvailable = !newerDownloaded && versionRow?.value != kCurrentKb.version;
      });
    }
  }
```

Add the `kbDownloadServiceProvider` in `lib/core/providers/repository_providers.dart`:

```dart
import '../services/kb_download_service.dart';

final kbDownloadServiceProvider = Provider<KbDownloadService>((ref) {
  return KbDownloadService();
});
```

Add the Settings UI section — insert right after the existing "AI Model" `_buildSectionCard` block (after its closing `const SizedBox(height: 16);` at line ~431 in the current file):

```dart
            // Knowledge Base
            _buildSectionCard(
              theme: theme,
              title: 'Knowledge Base',
              icon: Icons.menu_book_rounded,
              children: [
                ListTile(
                  title: Text('Installed version', style: theme.textTheme.bodyMedium),
                  subtitle: Text(_kbVersionInstalled ?? 'Unknown', style: theme.textTheme.labelLarge),
                ),
                if (_kbDownloading)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: _kbDownloadProgress,
                          color: AppTheme.emeraldGreen,
                          backgroundColor: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${(_kbDownloadProgress * 100).toStringAsFixed(0)}%',
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_kbUpdateAvailable)
                  ListTile(
                    title: const Text('Update available'),
                    trailing: TextButton(
                      onPressed: _downloadKbUpdate,
                      child: const Text('Update'),
                    ),
                  )
                else
                  const ListTile(title: Text('Up to date')),
              ],
            ),
            const SizedBox(height: 16),
```

Add the download handler:

```dart
  Future<void> _downloadKbUpdate() async {
    setState(() {
      _kbDownloading = true;
      _kbDownloadProgress = 0.0;
    });
    try {
      await ref.read(kbDownloadServiceProvider).downloadKb(
        kCurrentKb,
        onProgress: (progress) {
          if (mounted) setState(() => _kbDownloadProgress = progress.fraction);
        },
      );
      if (mounted) {
        setState(() => _kbDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Knowledge base updated. Restart the app to apply it.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _kbDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update knowledge base. Tap Update to retry.')),
        );
      }
    }
  }
```

Add the two new imports at the top of `settings_screen.dart`:

```dart
import '../../core/models/kb_catalog.dart';
import '../../core/providers/database_provider.dart' show knowledgeBaseDatabaseProvider;
```

Call `_checkKbStatus()` from wherever `_checkModelStatuses()` is already called in `initState`/lifecycle.

- [ ] **Step 5: Run `flutter analyze`**

Run: `flutter analyze`
Expected: zero errors. Fix any import/reference issues surfaced (e.g., if `main.dart`'s existing structure needs slightly different merging than the sketch in Step 3 — adapt to the actual existing code, don't blindly overwrite unrelated setup).

- [ ] **Step 6: Run the full suite**

Run: `flutter test`
Expected: all green.

- [ ] **Step 7: Manual verification**

Run: `flutter run -d linux` (or the appropriate local target). Verify:
- App launches without the `UnimplementedError`/`UnsupportedError` from earlier tasks.
- Quran reader shows real content beyond Al-Fatiha (open a surah like Al-Baqarah).
- Settings shows the Knowledge Base section with "Installed version: 1.0.0".
- Q&A screen's RAG search returns actually-relevant citations for a real question (e.g. ask about patience, confirm a Surah Al-Baqarah 2:153-style citation appears, not something unrelated).

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml .gitignore assets/databases/kb.db lib/core/providers/database_provider.dart lib/core/providers/repository_providers.dart lib/presentation/screens/settings_screen.dart lib/main.dart
git rm assets/databases/quran_base.db
git commit -m "feat: bundle real kb.db, wire KnowledgeBaseDatabase into the app, add Settings KB section"
```

---

### Task 9: CI release pipeline for `kb-v*` tags

**Files:**
- Create: `.github/workflows/build-kb-on-tag.yml`
- Modify: `lib/core/models/kb_catalog.dart` (final step — real size)

**Interfaces:** None new (uses everything from Tasks 4-6).

- [ ] **Step 1: Create the workflow**

Create `.github/workflows/build-kb-on-tag.yml`, mirroring `build-on-tag.yml`'s conventions:

```yaml
name: Build and Publish Knowledge Base

on:
  push:
    tags:
      - "kb-v[0-9]+.[0-9]+.[0-9]+*"

env:
  FLUTTER_VERSION: "3.44.2"

permissions:
  contents: write

jobs:
  build-kb:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable

      - run: flutter pub get

      - run: dart run build_runner build --delete-conflicting-outputs

      - name: Extract version from tag
        id: version
        run: echo "version=${GITHUB_REF_NAME#kb-v}" >> "$GITHUB_OUTPUT"

      - name: Build kb.db
        # `dart run` cannot host this — build_kb.dart transitively uses
        # rootBundle (via EmbeddingService/KnowledgeBaseDatabase.openBundled),
        # which needs Flutter engine bindings. tool/build_kb_runner.dart
        # (added in Task 6) hosts the same, unmodified build_kb.main() under
        # `flutter test`, which does provide them.
        run: |
          flutter test tool/build_kb_runner.dart --timeout=none \
            --dart-define=KB_OUTPUT=kb.db \
            --dart-define=KB_VERSION="${{ steps.version.outputs.version }}"

      - name: Compute checksum and size
        run: |
          sha256sum kb.db | tee kb.db.sha256
          stat -c '%s' kb.db | tee kb.db.size

      - uses: actions/upload-artifact@v7
        with:
          name: kb-release
          path: |
            kb.db
            kb.db.sha256
            kb.db.size
          if-no-files-found: error

  release:
    needs: build-kb
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v8
        with:
          name: kb-release
          path: artifacts

      - uses: softprops/action-gh-release@v3
        with:
          files: artifacts/*
          generate_release_notes: true
```

- [ ] **Step 2: Verify the workflow YAML is well-formed**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-kb-on-tag.yml'))"` (or any YAML linter available) — should parse with no errors. If no YAML tool is available, at minimum visually diff the structure against the working `build-on-tag.yml` for indentation consistency.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build-kb-on-tag.yml
git commit -m "ci: add kb-v* tag-triggered knowledge base build and release"
```

- [ ] **Step 4: Cut the real release (manual, requires repo push access and GH Actions minutes)**

```bash
git tag kb-v1.0.0
git push origin kb-v1.0.0
```

Wait for the workflow to complete, then download the published `kb.db` release asset and note its exact size:

```bash
gh release view kb-v1.0.0 --json assets --jq '.assets[] | select(.name == "kb.db") | .size'
```

- [ ] **Step 5: Fill in the real `kb_catalog.dart` values**

In `lib/core/models/kb_catalog.dart`, replace:

```dart
const KbInfo kCurrentKb = KbInfo(
  version: '1.0.0',
  filename: 'kb.db',
  sizeBytes: 0, // TODO(Task 9, final step): replace with the real, verified byte count.
);
```

with the real observed size from Step 4, e.g.:

```dart
const KbInfo kCurrentKb = KbInfo(
  version: '1.0.0',
  filename: 'kb.db',
  sizeBytes: 47239168, // Verified: gh release view kb-v1.0.0 (2026-07-05)
);
```

Also replace `REPLACE_WITH_ORG` in the `downloadUrl` getter with the actual GitHub org/repo.

Remove the `skip:` marker from Task 4's test:

```dart
  test('kCurrentKb.sizeBytes is filled in with the real published size', () {
    expect(kCurrentKb.sizeBytes, greaterThan(0));
  });
```

- [ ] **Step 6: Run the full suite**

Run: `flutter test`
Expected: all green, including the previously-skipped size test.

- [ ] **Step 7: Commit**

```bash
git add lib/core/models/kb_catalog.dart test/core/models/kb_catalog_test.dart
git commit -m "chore: pin real kb-v1.0.0 release size in kb_catalog.dart"
```

---

### Task 10: `Tracker.md` entry

**Files:**
- Modify: `Tracker.md`

**Interfaces:** None (documentation only).

- [ ] **Step 1: Add the new phase**

Append to `Tracker.md`, after the existing "Phase 11: Multi-Platform Configuration" section:

```markdown
### Phase 12: Knowledge Base v1 (Content + Real Embeddings)
*   [x] **Task 12.1:** Replace the placeholder 7-verse/1-hadith/1-tafsir database with a complete, authentically-sourced Quran (6,236 verses, Arabic/English/Bengali), Hadith (Sahih al-Bukhari + Sahih Muslim, Arabic/English/Bengali), and Tafsir Ibn Kathir (English/Bengali) knowledge base. (Completed: YYYY-MM-DD)
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
```

- [ ] **Step 2: Commit**

```bash
git add Tracker.md
git commit -m "docs: track Knowledge Base v1 phase in Tracker.md"
```
