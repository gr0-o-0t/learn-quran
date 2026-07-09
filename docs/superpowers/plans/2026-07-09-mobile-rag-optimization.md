# Mobile RAG Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut per-query LLM calls from two to one, add on-device reranking to fix wrong/irrelevant citations, shrink `kb.db`'s storage/RAM footprint via int8-quantized embeddings and dictionary-encoded BM25 postings, and add a genuinely tiny LLM tier so the app is usable (not just "less bad") on a 3-4GB RAM Android floor.

**Architecture:** See `docs/superpowers/specs/2026-07-09-mobile-rag-optimization-design.md` for the full design and decision log. Summary: drop the HyDE draft pass from `LlmService`; add a `RerankerService` (ONNX cross-encoder) as a new stage inside `RagRepository.search()` after RRF fusion; rebuild `kb.db` (schemaVersion 2→3) with int8 vectors and a `Bm25Terms` dictionary table; add a third `ModelInfo` catalog entry.

**Tech Stack:** Same as the existing pipeline — `onnxruntime` (Dart FFI ONNX Runtime), `bert_tokenizer` (WordPiece), Drift/SQLite, `llamadart` (llama.cpp GGUF).

## Global Constraints

- Fully offline: no new network calls anywhere in the app-side runtime path (the reranker model, like the embedding model, ships as a bundled asset — network calls only happen once, at build/dev time, to fetch that asset).
- No new tokenizer dependency: the reranker reuses the exact same `assets/models/bge_small_en_v1_5_vocab.txt` file already bundled (verified identical — both models share the standard BERT-base-uncased vocab; sha256 confirmed byte-identical).
- Requires a new KB version, `kb-v1.2.0` (schema change: `schemaVersion` 2→3). `tafsirs`/`hadiths`/`verses` tables' shape and content are unchanged.
- Reranker failure (model unavailable, or any scoring exception) must fall back to plain RRF order — never a fake/mock score.
- `RagRepository.search()`'s public signature and `RagSearchResult` shape do not change. `LlmService.generateGroundedResponseStream()`'s public signature does not change.
- The mock/no-engine path in `LlmService` (`_generateMockResponse`) and `daily_story_service.dart`'s use of `generateResponseStream` are out of scope and must be unaffected.
- BGE embeddings are always L2-normalized (`EmbeddingService._normalize`), so quantization uses a fixed scale (127), never a per-vector min/max.
- Every model/asset value (file size, revision/commit hash) must be the real, verified value — never an approximation — matching this project's existing convention (see `model_catalog.dart`'s doc comment and the exact-size verification step in the prior knowledge-base-v1 plan).

---

### Task 1: Shared ONNX runtime reference counting (`OrtRuntime`)

**Files:**
- Create: `lib/core/services/ort_runtime.dart`
- Modify: `lib/core/services/embedding_service.dart`
- Test: `test/core/services/ort_runtime_test.dart`

**Interfaces:**
- Produces: `OrtRuntime.acquire({void Function() initFn})`, `OrtRuntime.release({void Function() releaseFn})`, `OrtRuntime.resetForTesting()` — used by Task 2 (`RerankerService`) and this task's retrofit of `EmbeddingService`.

**Why this task exists:** `OrtEnv.instance.init()`/`release()` (the `onnxruntime` package's process-wide singleton) are NOT reference-counted. `EmbeddingService` currently calls both directly. Task 2 adds a second independent ONNX consumer (`RerankerService`). Without this fix, whichever service disposes first would tear down the native ONNX environment out from under the other — a real crash risk, not a hypothetical one. This must land before Task 2.

- [ ] **Step 1: Write the failing test**

Create `test/core/services/ort_runtime_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/services/ort_runtime.dart';

void main() {
  setUp(() {
    OrtRuntime.resetForTesting();
  });

  group('OrtRuntime', () {
    test('release without a matching acquire never throws and never calls releaseFn', () {
      var releaseCalls = 0;
      expect(() => OrtRuntime.release(releaseFn: () => releaseCalls++), returnsNormally);
      expect(releaseCalls, 0);
    });

    test('the first acquire calls initFn; later acquires before any release do not', () {
      var initCalls = 0;
      OrtRuntime.acquire(initFn: () => initCalls++);
      OrtRuntime.acquire(initFn: () => initCalls++);
      OrtRuntime.acquire(initFn: () => initCalls++);
      expect(initCalls, 1);
    });

    test('releaseFn only fires once every acquire has a matching release', () {
      var releaseCalls = 0;
      OrtRuntime.acquire(initFn: () {});
      OrtRuntime.acquire(initFn: () {});
      OrtRuntime.release(releaseFn: () => releaseCalls++);
      expect(releaseCalls, 0);
      OrtRuntime.release(releaseFn: () => releaseCalls++);
      expect(releaseCalls, 1);
    });

    test('a fresh acquire after the ref count returns to zero calls initFn again', () {
      var initCalls = 0;
      OrtRuntime.acquire(initFn: () => initCalls++);
      OrtRuntime.release(releaseFn: () {});
      OrtRuntime.acquire(initFn: () => initCalls++);
      expect(initCalls, 2);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/services/ort_runtime_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'learn_quran' in 'package:learn_quran/core/services/ort_runtime.dart'` (the file doesn't exist yet).

- [ ] **Step 3: Write the implementation**

Create `lib/core/services/ort_runtime.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:onnxruntime/onnxruntime.dart';

/// Thin reference-counted wrapper around the process-wide `OrtEnv`
/// singleton. `OrtEnv.instance.init()`/`release()` are NOT themselves
/// reference-counted: a second `init()` call leaks the previous native
/// environment pointer, and `release()` tears the environment down
/// unconditionally. Once more than one service uses ONNX Runtime
/// independently (`EmbeddingService`, and `RerankerService`), each calling
/// `OrtEnv.instance.init()`/`release()` directly would corrupt state for
/// the other the moment either one disposes while the other is still
/// active. This makes "initialize once, tear down once the last user is
/// done" explicit and testable.
class OrtRuntime {
  static int _refCount = 0;

  static void _defaultInit() => OrtEnv.instance.init();
  static void _defaultRelease() => OrtEnv.instance.release();

  /// Call once per service's `init()`. Only actually initializes the
  /// native environment on the very first call since the ref count last
  /// reached zero.
  static void acquire({void Function() initFn = _defaultInit}) {
    if (_refCount == 0) {
      initFn();
    }
    _refCount++;
  }

  /// Call once per service's `dispose()`. Only actually releases the
  /// native environment once every `acquire()` has a matching `release()`.
  /// Safe to call with no prior `acquire()` (a no-op).
  static void release({void Function() releaseFn = _defaultRelease}) {
    if (_refCount == 0) return;
    _refCount--;
    if (_refCount == 0) {
      releaseFn();
    }
  }

  /// Test-only: resets the ref count so tests don't leak state into each
  /// other via this process-wide static. Never called from production code.
  @visibleForTesting
  static void resetForTesting() {
    _refCount = 0;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/services/ort_runtime_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Retrofit `EmbeddingService` to use `OrtRuntime`**

In `lib/core/services/embedding_service.dart`, add the import:

```dart
import 'ort_runtime.dart';
```

Change the `init()` method's real-ONNX branch — replace:

```dart
      OrtEnv.instance.init();
      final bytes = await rootBundle.load('assets/models/bge_small_en_v1_5.onnx');
```

with:

```dart
      OrtRuntime.acquire();
      final bytes = await rootBundle.load('assets/models/bge_small_en_v1_5.onnx');
```

Change `dispose()` — replace:

```dart
  void dispose() {
    _session?.release();
    if (_initialized && !_useMock) {
      OrtEnv.instance.release();
    }
  }
```

with:

```dart
  void dispose() {
    _session?.release();
    if (_initialized && !_useMock) {
      OrtRuntime.release();
    }
  }
```

The `import 'package:onnxruntime/onnxruntime.dart';` line stays (still needed for `OrtSession`, `OrtSessionOptions`, `OrtValueTensor`, `OrtRunOptions`).

- [ ] **Step 6: Run the full existing test suite to confirm no regression**

Run: `flutter test test/core/services/embedding_service_test.dart`
Expected: PASS (4 tests) — these tests use `EmbeddingService(forceMock: true)`, which never touches `OrtRuntime` at all (the mock branch returns before reaching `init()`'s real-ONNX code), so this change is behaviorally invisible to them.

- [ ] **Step 7: Commit**

```bash
git add lib/core/services/ort_runtime.dart lib/core/services/embedding_service.dart test/core/services/ort_runtime_test.dart
git commit -m "feat(rag): add reference-counted OrtRuntime wrapper, retrofit EmbeddingService"
```

---

### Task 2: On-device reranker (`RerankerService`)

**Files:**
- Create: `lib/core/services/reranker_service.dart`
- Test: `test/core/services/reranker_service_test.dart`
- Fetch (asset, see Step 1): `assets/models/ms_marco_minilm_l6_v2.onnx`
- Modify: `.gitignore`, `pubspec.yaml` (no dependency changes — assets already declared broadly via `assets/models/`, `.gitignore`'s per-file `.onnx` allowlist needs a new line)

**Interfaces:**
- Consumes: `lib/core/services/ort_runtime.dart`'s `OrtRuntime.acquire()`/`OrtRuntime.release()` (Task 1). Reuses `assets/models/bge_small_en_v1_5_vocab.txt` (already bundled) — verified byte-identical to `Xenova/ms-marco-MiniLM-L-6-v2`'s own `vocab.txt` (both are the standard BERT-base-uncased WordPiece vocabulary), so no new vocab asset is fetched.
- Produces: `typedef RerankScoreFn = Future<double?> Function(String query, String passage)`; `class RerankerService { RerankerService({bool forceMock, RerankScoreFn? scoreOverride}); Future<double?> score(String query, String passage); void dispose(); }` — `score` returns `null` when the reranker is unavailable (forceMock, or the real model failed to load/score) — callers (Task 3) MUST treat `null` as "skip reranking, fall back to RRF order", never as a real low score.

**Verified facts for this task (do not re-derive, use these exact values):**
- Model: `Xenova/ms-marco-MiniLM-L-6-v2`, file `onnx/model_uint8.onnx`, exact size **23012420 bytes**.
- `config.json` confirms: `architectures: ["BertForSequenceClassification"]`, `id2label: {"0": "LABEL_0"}` (single output label — the model outputs one relevance logit per example, shape `[1, 1]`, not a 2-class softmax), `type_vocab_size: 2` (uses `token_type_ids` to distinguish the query segment from the passage segment), `max_position_embeddings: 512`, `sbert_ce_default_activation_function: Identity` (raw logit, no sigmoid — fine, only relative ranking matters here).
- `bert_tokenizer` 1.1.1's `BertTokenizer` class has **no public method to convert tokens to vocabulary ids** — only `tokenize(String) -> List<String>` (word-piece splitting, public) and `prepareNerInput` (which always builds a *single*-segment `[CLS] tokens [SEP]`, unusable for a query+passage pair with two segments). This task builds its own small token→id index by parsing the same `vocab.txt` format directly (one line per token, in vocabulary-id order) — this is not a hack around the package, it's the same parsing `BertTokenizer.fromStringContent` itself does internally, just also kept accessible here.

- [ ] **Step 1: Fetch the model asset**

```bash
curl -L -o assets/models/ms_marco_minilm_l6_v2.onnx \
  "https://huggingface.co/Xenova/ms-marco-MiniLM-L-6-v2/resolve/main/onnx/model_uint8.onnx"
```

Run: `ls -la assets/models/ms_marco_minilm_l6_v2.onnx`
Expected: exactly **23012420** bytes. If it differs, stop and re-verify the source before proceeding — do not assume a size mismatch is harmless (same discipline as the existing `bge_small_en_v1_5.onnx` fetch step).

- [ ] **Step 2: Allow the new asset past `.gitignore`**

In `.gitignore`, find these lines:

```
assets/models/*.onnx
!assets/models/bge_small_en_v1_5.onnx
assets/models/*.bin
```

Change to:

```
assets/models/*.onnx
!assets/models/bge_small_en_v1_5.onnx
!assets/models/ms_marco_minilm_l6_v2.onnx
assets/models/*.bin
```

- [ ] **Step 3: Write the failing test**

Create `test/core/services/reranker_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/services/reranker_service.dart';

void main() {
  group('RerankerService', () {
    test('forceMock returns null (unavailable) without touching ONNX', () async {
      final service = RerankerService(forceMock: true);
      final score = await service.score('a query', 'a passage');
      expect(score, isNull);
    });

    test('scoreOverride bypasses the real model entirely, for both text and score', () async {
      final service = RerankerService(
        scoreOverride: (query, passage) async => passage.contains('relevant') ? 5.0 : -5.0,
      );
      expect(await service.score('q', 'this is relevant text'), 5.0);
      expect(await service.score('q', 'this is off-topic text'), -5.0);
    });

    test('scoreOverride receives the exact query and passage text passed in', () async {
      String? capturedQuery;
      String? capturedPassage;
      final service = RerankerService(
        scoreOverride: (query, passage) async {
          capturedQuery = query;
          capturedPassage = passage;
          return 0.0;
        },
      );
      await service.score('the query text', 'the passage text');
      expect(capturedQuery, 'the query text');
      expect(capturedPassage, 'the passage text');
    });
  });
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/core/services/reranker_service_test.dart`
Expected: FAIL — `reranker_service.dart` doesn't exist yet.

- [ ] **Step 5: Write the implementation**

Create `lib/core/services/reranker_service.dart`:

```dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:bert_tokenizer/bert_tokenizer.dart';
import 'ort_runtime.dart';

const _maxTokenLength = 256;

/// Test/override seam: bypasses the real ONNX model entirely — used by
/// tests that want to control exactly what score a given (query, passage)
/// pair gets, without a real model file in the test environment.
typedef RerankScoreFn = Future<double?> Function(String query, String passage);

/// Scores how relevant a (query, passage) pair is, using a small on-device
/// cross-encoder (Xenova/ms-marco-MiniLM-L-6-v2, int8 ONNX, ~23MB) — used
/// by RagRepository to reorder its fused RRF candidates before truncating
/// to the final result count, since RRF fusion alone does not directly
/// model query-passage relevance the way a cross-encoder does.
class RerankerService {
  OrtSession? _session;
  BertTokenizer? _tokenizer;
  Map<String, int>? _vocabIndex;
  bool _initialized = false;
  bool _useMock = false;
  final RerankScoreFn? _scoreOverride;

  RerankerService({bool forceMock = false, RerankScoreFn? scoreOverride})
      : _useMock = forceMock,
        _scoreOverride = scoreOverride;

  Future<void> init() async {
    if (_initialized) return;

    if (_useMock) {
      _initialized = true;
      return;
    }

    try {
      // Reuses the embedding model's own vocab.txt — verified byte-
      // identical to this reranker's vocab (both are standard
      // BERT-base-uncased WordPiece vocabularies), so no second vocab
      // asset is bundled.
      final vocabData = await rootBundle.loadString('assets/models/bge_small_en_v1_5_vocab.txt');
      _tokenizer = BertTokenizer.fromStringContent(vocabData);
      _vocabIndex = _buildVocabIndex(vocabData);

      OrtRuntime.acquire();
      final bytes = await rootBundle.load('assets/models/ms_marco_minilm_l6_v2.onnx');
      final sessionOptions = OrtSessionOptions();
      _session = OrtSession.fromBuffer(bytes.buffer.asUint8List(), sessionOptions);
      _initialized = true;
    } catch (e, st) {
      // Fallback to "unavailable" (score() returns null) if assets aren't
      // present or init fails — unlike EmbeddingService, there is no
      // meaningful "mock score" to fall back to, so callers must skip
      // reranking entirely on this signal, not treat it as a real result.
      debugPrint('RerankerService.init failed, reranking will be skipped: $e\n$st');
      _useMock = true;
      _initialized = true;
    }
  }

  /// Parses the same `vocab.txt` line-per-token format
  /// `BertTokenizer.fromStringContent` parses internally, so word-piece
  /// tokens (from the tokenizer's own public `tokenize()`) can be mapped
  /// to vocabulary ids — `BertTokenizer` has no public tokens->ids method
  /// itself (only the reverse, `convertIdsToTokens`).
  Map<String, int> _buildVocabIndex(String vocabContent) {
    final lines = vocabContent.split(RegExp(r'\r?\n'));
    final index = <String, int>{};
    var i = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      index[trimmed] = i;
      i++;
    }
    return index;
  }

  /// Returns a relevance score for (query, passage) — higher means more
  /// relevant — or `null` if the reranker is unavailable (forceMock, init
  /// failure, or a scoring exception). Callers MUST treat `null` as "skip
  /// reranking for this pair", never as a real (e.g. zero or negative)
  /// score.
  Future<double?> score(String query, String passage) async {
    if (_scoreOverride != null) return _scoreOverride!(query, passage);

    await init();
    if (_useMock) return null;

    try {
      final tokenizer = _tokenizer!;
      final vocabIndex = _vocabIndex!;
      final queryTokens = tokenizer.tokenize(query);
      final passageTokens = tokenizer.tokenize(passage);

      // Reserve 3 positions for [CLS] + [SEP] + [SEP]. Queries here are
      // short (a user's question); passages are the ones that can run
      // long (a full tafsir chunk), so truncate the passage, not the
      // query, when the pair doesn't fit.
      final maxContentLength = _maxTokenLength - 3;
      var truncatedQuery = queryTokens;
      if (truncatedQuery.length > maxContentLength) {
        truncatedQuery = truncatedQuery.sublist(0, maxContentLength);
      }
      final remaining = maxContentLength - truncatedQuery.length;
      var truncatedPassage = passageTokens;
      if (truncatedPassage.length > remaining) {
        truncatedPassage = truncatedPassage.sublist(0, remaining);
      }

      final tokens = [
        BertTokenizer.clsToken,
        ...truncatedQuery,
        BertTokenizer.sepToken,
        ...truncatedPassage,
        BertTokenizer.sepToken,
      ];
      final segmentIds = [
        ...List.filled(truncatedQuery.length + 2, 0), // [CLS] + query + [SEP]
        ...List.filled(truncatedPassage.length + 1, 1), // passage + [SEP]
      ];
      final unkId = vocabIndex[BertTokenizer.unkToken]!;
      final inputIds = tokens.map((t) => vocabIndex[t] ?? unkId).toList();
      final attentionMask = List<int>.filled(inputIds.length, 1);

      final shape = [1, inputIds.length];
      final inputIdsTensor = OrtValueTensor.createTensorWithDataList(inputIds, shape);
      final attentionMaskTensor = OrtValueTensor.createTensorWithDataList(attentionMask, shape);
      final tokenTypeIdsTensor = OrtValueTensor.createTensorWithDataList(segmentIds, shape);

      final inputs = {
        'input_ids': inputIdsTensor,
        'attention_mask': attentionMaskTensor,
        'token_type_ids': tokenTypeIdsTensor,
      };
      final runOptions = OrtRunOptions();
      final outputs = await _session!.runAsync(runOptions, inputs);

      // A single relevance logit per example: output shape [1, 1] (see
      // config.json's id2label — one label, not a 2-class softmax).
      double? logit;
      final rawOutput = outputs != null && outputs.isNotEmpty ? outputs[0]?.value : null;
      if (rawOutput is List && rawOutput.isNotEmpty) {
        final batch0 = rawOutput[0];
        if (batch0 is List && batch0.isNotEmpty) {
          logit = (batch0[0] as num).toDouble();
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

      if (logit == null) {
        debugPrint('RerankerService.score got no usable output for "$query" — treating as unavailable.');
      }
      return logit;
    } catch (e, st) {
      debugPrint('RerankerService.score failed for "$query": $e\n$st');
      return null;
    }
  }

  void dispose() {
    _session?.release();
    if (_initialized && !_useMock) {
      OrtRuntime.release();
    }
  }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/core/services/reranker_service_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 7: Commit**

```bash
git add assets/models/ms_marco_minilm_l6_v2.onnx .gitignore lib/core/services/reranker_service.dart test/core/services/reranker_service_test.dart
git commit -m "feat(rag): add on-device cross-encoder RerankerService"
```

---

### Task 3: Wire the reranker into `RagRepository.search()`

**Files:**
- Modify: `lib/data/repositories/rag_repository.dart`
- Test: `test/data/repositories/rag_repository_test.dart`

**Interfaces:**
- Consumes: `RerankerService` (Task 2) — `RagRepository`'s constructor gains an optional 3rd positional parameter, defaulting to a real `RerankerService()` if not provided (backward compatible — every existing call site passing only 2 args is unaffected).
- Produces: no change to `RagRepository.search(String query, {int limit = 5})`'s signature or `RagSearchResult` shape — reranking is an internal stage.

- [ ] **Step 1: Write the failing tests**

In `test/data/repositories/rag_repository_test.dart`, add this import:

```dart
import 'package:learn_quran/core/services/reranker_service.dart';
```

Add this new `group` at the end of `main()`, right before the closing `}`:

```dart
  group('RagRepository reranking', () {
    test('reranker reorders the fused RRF candidates by its own relevance score', () async {
      // hadith 2 has no special embedding/BM25 relationship to the query
      // below (its mock embedding is unrelated, and it has no BM25
      // postings) — only the reranker override declaring it maximally
      // relevant should be able to put it first.
      await db.into(db.hadiths).insert(HadithsCompanion.insert(
            id: const drift.Value(2),
            bookName: 'Sahih Muslim',
            hadithNumber: '99',
            chapterTitle: 'Zakat',
            arabicText: 'زَكَاة',
            englishText: 'A distinctive passage the reranker will prefer.',
            banglaText: 'যাকাত',
          ));
      await _insertVector(
        db,
        RagRepository.hadithOffset + 2,
        await embeddingService.getEmbedding('A distinctive passage the reranker will prefer.'),
      );

      final reranker = RerankerService(
        scoreOverride: (query, passage) async => passage.contains('reranker will prefer') ? 100.0 : 0.0,
      );
      final repoWithReranker = RagRepository(db, embeddingService, reranker);

      final results = await repoWithReranker.search('name of Allah', limit: 1);

      expect(results, hasLength(1));
      expect(results.first.hadith?.id, 2);
    });

    test('falls back to RRF order (not an error) when the reranker is unavailable', () async {
      final reranker = RerankerService(forceMock: true);
      final repoWithReranker = RagRepository(db, embeddingService, reranker);

      final results = await repoWithReranker.search('name of Allah', limit: 2);

      expect(results, isNotEmpty);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/rag_repository_test.dart`
Expected: FAIL — `RagRepository`'s constructor doesn't accept a 3rd positional argument yet, and `results.first.hadith?.id` would be `1` (the un-reranked RRF winner), not `2`.

- [ ] **Step 3: Write the implementation**

In `lib/data/repositories/rag_repository.dart`, add the import:

```dart
import '../../core/services/reranker_service.dart';
```

Change the class fields and constructor — replace:

```dart
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
```

with:

```dart
class RagRepository {
  final KnowledgeBaseDatabase _db;
  final EmbeddingService _embeddingService;
  final RerankerService _rerankerService;
  late final Bm25Index _bm25Index;

  static const int hadithOffset = 100000;
  static const int tafsirOffset = 200000;
  static const int _embeddingDimensions = 384;
  static const int _rrfK = 60;
  static const int _rerankCandidateCount = 20;

  Float32List? _embeddingMatrix;
  List<int>? _embeddingDocIds;

  RagRepository(this._db, this._embeddingService, [RerankerService? rerankerService])
      : _rerankerService = rerankerService ?? RerankerService() {
    _bm25Index = Bm25Index(_db);
  }
```

Change `search()` — replace:

```dart
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
```

with:

```dart
  Future<List<RagSearchResult>> search(String query, {int limit = 5}) async {
    final embeddingResults = await _embeddingSearch(query, limit: 20);
    final bm25Results = await _bm25Index.search(query, limit: 20);
    final fused = _reciprocalRankFusion(embeddingResults, bm25Results, limit: _rerankCandidateCount);

    final candidates = <RagSearchResult>[];
    for (final entry in fused) {
      final match = await _buildSearchResult(entry.key, entry.value);
      if (match.verse != null || match.hadith != null || match.tafsir != null) {
        candidates.add(match);
      }
    }

    final reranked = await _rerank(query, candidates);
    return reranked.take(limit).toList();
  }

  /// Reranks [candidates] by relevance to [query] using [_rerankerService],
  /// highest score first. If the reranker is unavailable or any single
  /// scoring call fails, bails out to the original (RRF-fused) order for
  /// every candidate — reranking either fully succeeds or is fully skipped,
  /// never partially applied.
  Future<List<RagSearchResult>> _rerank(String query, List<RagSearchResult> candidates) async {
    if (candidates.isEmpty) return candidates;

    final scored = <MapEntry<RagSearchResult, double>>[];
    for (final candidate in candidates) {
      final text = citationFor(candidate).text;
      final score = await _rerankerService.score(query, text);
      if (score == null) return candidates;
      scored.add(MapEntry(candidate, score));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/repositories/rag_repository_test.dart`
Expected: PASS (all tests, including the 2 new ones). The existing "search returns matching segments ordered by similarity" and "a document found only via BM25 ranks first..." tests use the default `RagRepository(db, embeddingService)` (no reranker argument) — its default `RerankerService()` gracefully falls back to unavailable (no real ONNX asset reachable from a plain `flutter test` run, same as `EmbeddingService`'s own real-model path), so `_rerank` bails to RRF order on the very first candidate and these tests' existing assertions are unaffected.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/rag_repository.dart test/data/repositories/rag_repository_test.dart
git commit -m "feat(rag): rerank RRF-fused candidates before truncating to the final result count"
```

---

### Task 4: Remove the HyDE draft pass from `LlmService`

**Files:**
- Modify: `lib/core/services/llm_service.dart`
- Test: `test/core/services/llm_service_test.dart`

**Interfaces:**
- Produces: `LlmService.generateGroundedResponseStream`'s signature and behavior contract are unchanged from the caller's perspective (still takes `question`, `ragRepository`, `onRetrieved`) — only its *internal* implementation changes (one LLM call instead of two, retrieval always on the raw question).

- [ ] **Step 1: Update the implementation**

In `lib/core/services/llm_service.dart`, remove the `_draftSystemPrompt` constant and simplify `generateGroundedResponseStream` — replace:

```dart
  static const _draftSystemPrompt =
      'You are a gentle, respectful Islamic teaching companion. Answer the '
      'question briefly and naturally from your own general knowledge — you '
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
```

with:

```dart
  /// RAG-grounded generation for the Q&A screen: hybrid retrieval
  /// ([ragRepository.search]) on the raw [question], then a single-pass
  /// [generateResponseStream] grounded in the retrieved references.
  ///
  /// This used to run a hidden "draft" LLM pass first (HyDE-style query
  /// rewriting: draft a hypothetical answer, retrieve using that instead of
  /// the raw question) — removed. It cost a full extra LLM generation per
  /// question (measurably too slow on low-RAM phones), and a bad or
  /// hallucinated draft could misdirect retrieval — a plausible cause of
  /// reported "wrong citation" cases, since the draft was never grounded in
  /// anything. RagRepository's hybrid embedding+BM25+reranking search
  /// (see rag_repository.dart) is now relied on directly to handle the raw
  /// question well.
  Stream<String> generateGroundedResponseStream(
    String question, {
    required RagRepository ragRepository,
    void Function(List<RagSearchResult> ragResults)? onRetrieved,
  }) async* {
    final ragResults = await ragRepository.search(question, limit: 5);
    onRetrieved?.call(ragResults);
    final ragContext = _buildRagContext(ragResults);

    yield* generateResponseStream(question, ragContext);
  }
```

- [ ] **Step 2: Update the tests**

In `test/core/services/llm_service_test.dart`, replace the entire `group('LlmService.generateGroundedResponseStream', ...)` block with:

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

    test('retrieves on the raw question and streams the mock response when no model is downloaded', () async {
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

    test('makes exactly one LLM call, for the refine pass, always on the original question', () async {
      final calls = <String>[];
      Future<Stream<String>?> chatOverride(String systemPrompt, String userPrompt, int maxTokens) async {
        calls.add(userPrompt);
        return Stream.value('Final grounded answer.');
      }
      final llm = LlmService(userRepo, downloadService, chatOverride);
      final recordingRepo = _RecordingRagRepository(kbDb, embeddingService);

      final stream = llm.generateGroundedResponseStream(
        'the original question',
        ragRepository: recordingRepo,
      );
      final response = await stream.join();

      expect(calls, ['the original question']);
      expect(recordingRepo.queries, ['the original question']);
      expect(response, 'Final grounded answer.');
    });

    test('onRetrieved fires with the results generateGroundedResponseStream retrieved', () async {
      Future<Stream<String>?> chatOverride(String systemPrompt, String userPrompt, int maxTokens) async {
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

(The `_RecordingRagRepository` class and the top-level `group('LlmService Tests', ...)` block above it are unchanged — leave them exactly as they are.)

- [ ] **Step 3: Run test to verify it passes**

Run: `flutter test test/core/services/llm_service_test.dart`
Expected: PASS (all tests — the `group('LlmService Tests', ...)` block's 6 tests are untouched by this task and must still pass; the rewritten `group('LlmService.generateGroundedResponseStream', ...)` block now has 3 tests instead of 5).

- [ ] **Step 4: Run the full suite once to catch any other reference to the removed draft behavior**

Run: `flutter test`
Expected: PASS (all tests) — `grep -rn "_draftSystemPrompt\|HyDE" lib/ test/` should return no matches after this task.

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/llm_service.dart test/core/services/llm_service_test.dart
git commit -m "refactor(rag): drop the HyDE draft pass, retrieve directly on the raw question"
```

---

### Task 5: BM25 term dictionary encoding (`Bm25Terms`)

**Files:**
- Modify: `lib/data/local/db/knowledge_base_database.dart`
- Modify: `lib/core/services/bm25_index.dart`
- Modify: `tool/build_kb.dart`
- Test: `test/core/services/bm25_index_test.dart`
- Test: `test/data/local/db/knowledge_base_database_test.dart`
- Test: `test/data/repositories/rag_repository_test.dart`

**Interfaces:**
- Produces: new `Bm25Terms` table (`termId` INTEGER primary key, `term` TEXT). `Bm25Postings.term` (TEXT) is replaced by `Bm25Postings.termId` (INTEGER). `Bm25Index.search()`'s public signature and return type (`Future<List<MapEntry<int, double>>>`) are unchanged — only its internal lookup path changes (term string → termId → postings, instead of querying postings by term string directly).
- Consumes (Task 6 also touches this file): none — this task and Task 6 both bump `schemaVersion` to 3; do them in this order so Task 6 doesn't also need its own version bump.

- [ ] **Step 1: Update the schema**

In `lib/data/local/db/knowledge_base_database.dart`, add a new table class right before `Bm25Postings`:

```dart
class Bm25Terms extends Table {
  IntColumn get termId => integer()();
  TextColumn get term => text()();

  @override
  Set<Column> get primaryKey => {termId};
}
```

Change `Bm25Postings` — replace:

```dart
class Bm25Postings extends Table {
  TextColumn get term => text()();
  IntColumn get docId => integer()();
  IntColumn get termFrequency => integer()();
}
```

with:

```dart
class Bm25Postings extends Table {
  IntColumn get termId => integer()();
  IntColumn get docId => integer()();
  IntColumn get termFrequency => integer()();
}
```

Add `Bm25Terms` to the `@DriftDatabase` tables list — replace:

```dart
@DriftDatabase(tables: [Verses, Hadiths, Tafsirs, KbMeta, TafsirChunks, Bm25Postings, Bm25DocStats])
```

with:

```dart
@DriftDatabase(tables: [Verses, Hadiths, Tafsirs, KbMeta, TafsirChunks, Bm25Terms, Bm25Postings, Bm25DocStats])
```

Bump `schemaVersion` and replace the index-creation helper — replace:

```dart
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
```

with:

```dart
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createVectorTable();
          await _createBm25Indexes();
        },
        beforeOpen: (details) async {
          await _createVectorTable();
          await _createBm25Indexes();
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

  Future<void> _createBm25Indexes() async {
    // idx_bm25_terms_term: resolves a query token's string to its termId
    // (Bm25Index.search's first lookup per token). idx_bm25_postings_term_id:
    // the equivalent of the old idx_bm25_postings_term index, now over the
    // termId column postings are actually queried by.
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_bm25_terms_term ON bm25_terms (term);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_bm25_postings_term_id ON bm25_postings (term_id);',
    );
  }
```

No `onUpgrade` is added — same as the prior schemaVersion 1→2 bump, an old kb.db (any version) fails Drift's default (throwing) upgrade strategy, which `openKnowledgeBaseDatabaseSafely` (in this same file) already catches and recovers from by deleting the stale file and opening a fresh, empty v3 database instead. This is exercised by the existing `test/data/local/db/knowledge_base_database_safe_open_test.dart` — no changes needed there.

- [ ] **Step 2: Update `Bm25Index`**

In `lib/core/services/bm25_index.dart`, replace the `search` method's term-lookup loop — replace:

```dart
      final scores = <int, double>{};
      for (final term in terms) {
        final postings = await (_db.select(_db.bm25Postings)..where((t) => t.term.equals(term))).get();
        if (postings.isEmpty) continue;
```

with:

```dart
      final scores = <int, double>{};
      for (final term in terms) {
        final termRow = await (_db.select(_db.bm25Terms)..where((t) => t.term.equals(term))).getSingleOrNull();
        if (termRow == null) continue; // term not in the dictionary — no matches for it
        final postings = await (_db.select(_db.bm25Postings)..where((t) => t.termId.equals(termRow.termId))).get();
        if (postings.isEmpty) continue;
```

(Nothing else in the method changes — the idf/tf/BM25 math below this loop is untouched.)

- [ ] **Step 3: Update `tool/build_kb.dart`**

In `tool/build_kb.dart`, replace `_embedAndIndex`'s batch-writing section — replace:

```dart
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
      // docId is Bm25DocStats's primary key, so Drift generates it as an
      // optional Value<int> in .insert(...) — must be wrapped, unlike the
      // plain-int docId on Bm25Postings above (no primary key there).
      batch.insert(
        db.bm25DocStats,
        Bm25DocStatsCompanion.insert(docId: Value(docId), docLength: docLengths[docId]!),
      );
    }
  });
```

with:

```dart
  stdout.writeln('Building BM25 index (${termFrequenciesByDoc.length} documents)...');
  final termIds = <String, int>{};
  int termIdFor(String term) => termIds.putIfAbsent(term, () => termIds.length + 1);

  await db.batch((batch) {
    for (final entry in termFrequenciesByDoc.entries) {
      final docId = entry.key;
      for (final termEntry in entry.value.entries) {
        final termId = termIdFor(termEntry.key);
        batch.insert(
          db.bm25Postings,
          Bm25PostingsCompanion.insert(termId: termId, docId: docId, termFrequency: termEntry.value),
        );
      }
      // docId is Bm25DocStats's primary key, so Drift generates it as an
      // optional Value<int> in .insert(...) — must be wrapped, unlike the
      // plain-int termId/docId on Bm25Postings above (no primary key there).
      batch.insert(
        db.bm25DocStats,
        Bm25DocStatsCompanion.insert(docId: Value(docId), docLength: docLengths[docId]!),
      );
    }
  });

  stdout.writeln('  BM25 term dictionary: ${termIds.length} unique terms');
  await db.batch((batch) {
    for (final entry in termIds.entries) {
      // termId is Bm25Terms's primary key, so Drift generates it as an
      // optional Value<int> in .insert(...) — must be wrapped.
      batch.insert(
        db.bm25Terms,
        Bm25TermsCompanion.insert(termId: Value(entry.value), term: entry.key),
      );
    }
  });
```

- [ ] **Step 4: Update `bm25_index_test.dart`**

In `test/core/services/bm25_index_test.dart`, replace the `setUp` block's batch insert — replace:

```dart
    await db.batch((batch) {
      batch.insertAll(db.bm25Postings, [
        Bm25PostingsCompanion.insert(term: 'patience', docId: 1, termFrequency: 2),
        Bm25PostingsCompanion.insert(term: 'prophet', docId: 1, termFrequency: 1),
        Bm25PostingsCompanion.insert(term: 'prophet', docId: 2, termFrequency: 3),
        Bm25PostingsCompanion.insert(term: 'prayer', docId: 3, termFrequency: 3),
      ]);
      batch.insertAll(db.bm25DocStats, [
        Bm25DocStatsCompanion.insert(docId: const Value(1), docLength: 3),
        Bm25DocStatsCompanion.insert(docId: const Value(2), docLength: 3),
        Bm25DocStatsCompanion.insert(docId: const Value(3), docLength: 3),
      ]);
      batch.insertAll(db.kbMeta, [
        KbMetaCompanion.insert(key: 'bm25_doc_count', value: '3'),
        KbMetaCompanion.insert(key: 'bm25_avg_doc_length', value: '3.0'),
      ]);
    });
```

with:

```dart
    await db.batch((batch) {
      batch.insertAll(db.bm25Terms, [
        Bm25TermsCompanion.insert(termId: const Value(1), term: 'patience'),
        Bm25TermsCompanion.insert(termId: const Value(2), term: 'prophet'),
        Bm25TermsCompanion.insert(termId: const Value(3), term: 'prayer'),
      ]);
      batch.insertAll(db.bm25Postings, [
        Bm25PostingsCompanion.insert(termId: 1, docId: 1, termFrequency: 2),
        Bm25PostingsCompanion.insert(termId: 2, docId: 1, termFrequency: 1),
        Bm25PostingsCompanion.insert(termId: 2, docId: 2, termFrequency: 3),
        Bm25PostingsCompanion.insert(termId: 3, docId: 3, termFrequency: 3),
      ]);
      batch.insertAll(db.bm25DocStats, [
        Bm25DocStatsCompanion.insert(docId: const Value(1), docLength: 3),
        Bm25DocStatsCompanion.insert(docId: const Value(2), docLength: 3),
        Bm25DocStatsCompanion.insert(docId: const Value(3), docLength: 3),
      ]);
      batch.insertAll(db.kbMeta, [
        KbMetaCompanion.insert(key: 'bm25_doc_count', value: '3'),
        KbMetaCompanion.insert(key: 'bm25_avg_doc_length', value: '3.0'),
      ]);
    });
```

Replace the "dropped entirely" test's table drops — replace:

```dart
      await db.customStatement('DROP TABLE bm25_postings');
      await db.customStatement('DROP TABLE bm25_doc_stats');
```

with:

```dart
      await db.customStatement('DROP TABLE bm25_postings');
      await db.customStatement('DROP TABLE bm25_doc_stats');
      await db.customStatement('DROP TABLE bm25_terms');
```

- [ ] **Step 5: Update `knowledge_base_database_test.dart`**

In `test/data/local/db/knowledge_base_database_test.dart`, replace the `'creates tafsir_chunks/bm25_postings/bm25_doc_stats tables'` test's BM25 portion — replace:

```dart
    await db.into(db.bm25Postings).insert(
          Bm25PostingsCompanion.insert(term: 'patience', docId: 1, termFrequency: 2),
        );
    final posting = await (db.select(db.bm25Postings)..where((t) => t.term.equals('patience'))).getSingle();
    expect(posting.docId, 1);
    expect(posting.termFrequency, 2);
```

with:

```dart
    await db.into(db.bm25Terms).insert(
          Bm25TermsCompanion.insert(termId: const Value(1), term: 'patience'),
        );
    await db.into(db.bm25Postings).insert(
          Bm25PostingsCompanion.insert(termId: 1, docId: 1, termFrequency: 2),
        );
    final posting = await (db.select(db.bm25Postings)..where((t) => t.termId.equals(1))).getSingle();
    expect(posting.docId, 1);
    expect(posting.termFrequency, 2);
```

Also rename the test's own title (it already says "creates tafsir_chunks/bm25_postings/bm25_doc_stats tables" — leave it as-is, `Bm25Terms` is exercised as a supporting detail of the same test, not worth a title change).

- [ ] **Step 6: Update `rag_repository_test.dart`'s BM25-specific test**

In `test/data/repositories/rag_repository_test.dart`, replace the `'a document found only via BM25 ranks first for an exact keyword match'` test's batch insert — replace:

```dart
      await db.batch((batch) {
        batch.insertAll(db.bm25Postings, [
          Bm25PostingsCompanion.insert(term: 'xenocryst', docId: RagRepository.hadithOffset + 2, termFrequency: 1),
        ]);
        // docId is Bm25DocStats's primary key, so Drift generates it as an
        // optional Value<int> in .insert(...) — must be wrapped, unlike the
        // plain-int docId on Bm25Postings above (no primary key there).
        batch.insertAll(db.bm25DocStats, [
          Bm25DocStatsCompanion.insert(docId: const drift.Value(RagRepository.hadithOffset + 2), docLength: 6),
        ]);
        batch.insertAll(db.kbMeta, [
          KbMetaCompanion.insert(key: 'bm25_doc_count', value: '4'),
          KbMetaCompanion.insert(key: 'bm25_avg_doc_length', value: '6.0'),
        ]);
      });
```

with:

```dart
      await db.batch((batch) {
        batch.insertAll(db.bm25Terms, [
          Bm25TermsCompanion.insert(termId: const drift.Value(1), term: 'xenocryst'),
        ]);
        batch.insertAll(db.bm25Postings, [
          Bm25PostingsCompanion.insert(termId: 1, docId: RagRepository.hadithOffset + 2, termFrequency: 1),
        ]);
        // docId is Bm25DocStats's primary key, so Drift generates it as an
        // optional Value<int> in .insert(...) — must be wrapped, unlike the
        // plain-int termId/docId on Bm25Postings above (no primary key there).
        batch.insertAll(db.bm25DocStats, [
          Bm25DocStatsCompanion.insert(docId: const drift.Value(RagRepository.hadithOffset + 2), docLength: 6),
        ]);
        batch.insertAll(db.kbMeta, [
          KbMetaCompanion.insert(key: 'bm25_doc_count', value: '4'),
          KbMetaCompanion.insert(key: 'bm25_avg_doc_length', value: '6.0'),
        ]);
      });
```

- [ ] **Step 7: Regenerate Drift code and run the full suite**

Run:

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test
```

Expected: PASS (all tests). If `flutter analyze` reports anything, fix it before proceeding.

- [ ] **Step 8: Commit**

```bash
git add lib/data/local/db/knowledge_base_database.dart lib/core/services/bm25_index.dart tool/build_kb.dart \
  test/core/services/bm25_index_test.dart test/data/local/db/knowledge_base_database_test.dart test/data/repositories/rag_repository_test.dart
git commit -m "feat(kb): dictionary-encode BM25 postings (Bm25Terms), schemaVersion 2->3"
```

---

### Task 6: int8-quantized embedding vectors

**Files:**
- Create: `lib/core/utils/embedding_quantization.dart`
- Modify: `tool/build_kb.dart`
- Modify: `lib/data/repositories/rag_repository.dart`
- Test: `test/core/utils/embedding_quantization_test.dart`
- Test: `test/data/repositories/rag_repository_test.dart`

**Interfaces:**
- Produces: `int quantizeComponent(double value)`, `Int8List quantizeVector(List<double> vector)` — used by both `tool/build_kb.dart` (storage) and `RagRepository` (runtime query quantization), so the two never drift apart on scale/rounding.
- Consumes: `EmbeddingService.getEmbedding` always returns an L2-normalized vector (every component in `[-1, 1]`) — this is why a single fixed scale works with no per-vector min/max.

- [ ] **Step 1: Write the failing test**

Create `test/core/utils/embedding_quantization_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/utils/embedding_quantization.dart';

void main() {
  group('quantizeComponent', () {
    test('maps 1.0 to the max int8 scale value', () {
      expect(quantizeComponent(1.0), 127);
    });

    test('maps -1.0 to the min representable value', () {
      expect(quantizeComponent(-1.0), -127);
    });

    test('maps 0.0 to 0', () {
      expect(quantizeComponent(0.0), 0);
    });

    test('clamps values that round outside the int8 range', () {
      expect(quantizeComponent(1.5), 127);
      expect(quantizeComponent(-1.5), -127);
    });

    test('rounds to the nearest integer', () {
      expect(quantizeComponent(0.6), 76); // round(0.6 * 127) = round(76.2) = 76
    });
  });

  group('quantizeVector', () {
    test('quantizes every component and preserves length', () {
      final result = quantizeVector([1.0, -1.0, 0.0, 0.6]);
      expect(result.length, 4);
      expect(result[0], 127);
      expect(result[1], -127);
      expect(result[2], 0);
      expect(result[3], 76);
    });

    test('returns an empty Int8List for an empty vector', () {
      expect(quantizeVector([]).length, 0);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/utils/embedding_quantization_test.dart`
Expected: FAIL — `embedding_quantization.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

Create `lib/core/utils/embedding_quantization.dart`:

```dart
import 'dart:typed_data';

/// Fixed-scale int8 quantization for L2-normalized embedding vectors.
/// `EmbeddingService.getEmbedding` always returns a unit-length vector, so
/// every component is bounded to `[-1, 1]` — a fixed scale (mapping to the
/// signed int8 range, -127..127) needs no per-vector min/max, unlike
/// general-purpose quantization schemes over unbounded values.
const int quantizationScale = 127;

int quantizeComponent(double value) {
  final scaled = (value * quantizationScale).round();
  if (scaled > quantizationScale) return quantizationScale;
  if (scaled < -quantizationScale) return -quantizationScale;
  return scaled;
}

Int8List quantizeVector(List<double> vector) {
  final result = Int8List(vector.length);
  for (var i = 0; i < vector.length; i++) {
    result[i] = quantizeComponent(vector[i]);
  }
  return result;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/utils/embedding_quantization_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 5: Update `tool/build_kb.dart`'s vector storage**

Add the import:

```dart
import 'package:learn_quran/core/utils/embedding_quantization.dart';
```

Replace `_insertVector` — replace:

```dart
Future<void> _insertVector(KnowledgeBaseDatabase db, int rowid, List<double> embedding) async {
  final float32list = Float32List.fromList(embedding);
  final blob = float32list.buffer.asUint8List();
  await db.customStatement(
    'INSERT OR REPLACE INTO vec_knowledge_base(rowid, embedding) VALUES (?, ?)',
    [rowid, blob],
  );
}
```

with:

```dart
Future<void> _insertVector(KnowledgeBaseDatabase db, int rowid, List<double> embedding) async {
  final int8Vector = quantizeVector(embedding);
  final blob = int8Vector.buffer.asUint8List();
  await db.customStatement(
    'INSERT OR REPLACE INTO vec_knowledge_base(rowid, embedding) VALUES (?, ?)',
    [rowid, blob],
  );
}
```

- [ ] **Step 6: Update `RagRepository`'s embedding cache and dot product**

In `lib/data/repositories/rag_repository.dart`, add the import:

```dart
import '../../core/utils/embedding_quantization.dart';
```

Replace `_ensureEmbeddingCache` — replace:

```dart
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
```

with:

```dart
  Future<void> _ensureEmbeddingCache() async {
    if (_embeddingMatrix != null) return;

    final rows = await _db.customSelect('SELECT rowid, embedding FROM vec_knowledge_base').get();
    final docIds = <int>[];
    final matrix = Int8List(rows.length * _embeddingDimensions);

    for (var i = 0; i < rows.length; i++) {
      final rowid = rows[i].read<int>('rowid');
      final blob = rows[i].read<Uint8List>('embedding');
      final int8s = Int8List.sublistView(blob);
      docIds.add(rowid);
      final offset = i * _embeddingDimensions;
      final count = min(_embeddingDimensions, int8s.length);
      for (var d = 0; d < count; d++) {
        matrix[offset + d] = int8s[d];
      }
    }

    _embeddingDocIds = docIds;
    _embeddingMatrix = matrix;
  }
```

Replace the `_dotProduct` (SIMD) method and `_embeddingSearch` — replace:

```dart
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
    const laneCount = _embeddingDimensions ~/ 4;
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
```

with:

```dart
  /// Integer dot product between [query] and the doc embedding stored at
  /// [docIndex] in [matrix]. Both are int8-quantized (see
  /// core/utils/embedding_quantization.dart) — Dart's `dart:typed_data` has
  /// no int8 SIMD type, so this is a plain scalar loop; at this corpus size
  /// (tens of thousands of docs) that's expected to still be fast enough on
  /// a phone CPU (see the design doc's A1/A3 assumptions) without needing
  /// the Float32x4 SIMD the old float32 version used.
  int _dotProductInt8(Int8List query, Int8List matrix, int docIndex) {
    final base = docIndex * _embeddingDimensions;
    var sum = 0;
    for (var d = 0; d < _embeddingDimensions; d++) {
      sum += query[d] * matrix[base + d];
    }
    return sum;
  }

  Future<List<MapEntry<int, double>>> _embeddingSearch(String query, {int limit = 20}) async {
    await _ensureEmbeddingCache();
    final docIds = _embeddingDocIds!;
    final matrix = _embeddingMatrix!;
    if (docIds.isEmpty) return const [];

    final queryVector = await _embeddingService.getEmbedding(query, isQuery: true);
    final queryInt8 = quantizeVector(queryVector);

    final scored = <MapEntry<int, double>>[];
    for (var i = 0; i < docIds.length; i++) {
      scored.add(MapEntry(docIds[i], _dotProductInt8(queryInt8, matrix, i).toDouble()));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).toList();
  }
```

The `Float32List? _embeddingMatrix;` field declaration near the top of the class must also change to `Int8List? _embeddingMatrix;` — replace:

```dart
  Float32List? _embeddingMatrix;
  List<int>? _embeddingDocIds;
```

with:

```dart
  Int8List? _embeddingMatrix;
  List<int>? _embeddingDocIds;
```

- [ ] **Step 7: Update the test helper that writes vectors**

In `test/data/repositories/rag_repository_test.dart`, replace the `_insertVector` helper — replace:

```dart
Future<void> _insertVector(KnowledgeBaseDatabase db, int rowid, List<double> embedding) async {
  final float32list = Float32List.fromList(embedding);
  final blob = float32list.buffer.asUint8List();
  await db.customStatement(
    'INSERT OR REPLACE INTO vec_knowledge_base(rowid, embedding) VALUES (?, ?)',
    [rowid, blob],
  );
}
```

with:

```dart
Future<void> _insertVector(KnowledgeBaseDatabase db, int rowid, List<double> embedding) async {
  final int8Vector = quantizeVector(embedding);
  final blob = int8Vector.buffer.asUint8List();
  await db.customStatement(
    'INSERT OR REPLACE INTO vec_knowledge_base(rowid, embedding) VALUES (?, ?)',
    [rowid, blob],
  );
}
```

Add the import:

```dart
import 'package:learn_quran/core/utils/embedding_quantization.dart';
```

- [ ] **Step 8: Run the full suite**

Run: `flutter analyze && flutter test`
Expected: `flutter analyze`: No issues found. `flutter test`: PASS (all tests) — the mock embedding path (`EmbeddingService(forceMock: true)`) still returns unit-length float vectors, which quantize and round-trip through int8 fine for the existing similarity-ordering assertions (int8 quantization of even mock vectors preserves enough relative signal for "which of 3-4 tiny candidates ranks first" — the same tolerance the existing tests already rely on for approximate mock-embedding similarity).

- [ ] **Step 9: Commit**

```bash
git add lib/core/utils/embedding_quantization.dart tool/build_kb.dart lib/data/repositories/rag_repository.dart \
  test/core/utils/embedding_quantization_test.dart test/data/repositories/rag_repository_test.dart
git commit -m "feat(kb): int8-quantize embedding vectors (storage and runtime cache)"
```

---

### Task 7: Tiny LLM tier + Settings default-selection fix

**Files:**
- Modify: `lib/core/models/model_catalog.dart`
- Modify: `lib/presentation/screens/settings_screen.dart`
- Test: `test/core/models/model_catalog_test.dart`

**Interfaces:**
- Produces: a third `ModelInfo` catalog entry, `id: 'tiny'`, with no `recommendedAboveRamGb` (the new fallback/floor). `e2b` gains an explicit `recommendedAboveRamGb: 4.0` (it used to be the implicit floor via having no threshold at all).

**Verified facts for this task (do not re-derive):**
- `Qwen/Qwen2.5-0.5B-Instruct-GGUF`, file `qwen2.5-0.5b-instruct-q4_k_m.gguf`, commit `9217f5db79a29953eb74d5343926648285ec7e67`, exact size **491400032 bytes**, license Apache-2.0 (confirmed via the repo's own `cardData.license`).
- **Real bug found while reading `settings_screen.dart` for this task**: `_selectedModel` initializes to the hardcoded string `'e2b'` (line 24), and `_loadSettings()` falls back to the hardcoded string `'e2b'` (line ~343) when the user has never explicitly picked a model. Today this happens to coincide with `recommendedModelFor`'s own fallback (e2b has no threshold, so it's the RAM-based default for any RAM below 6.0). Once `tiny` becomes the new no-threshold fallback, this hardcoding would make Settings *display* `'e2b'` as selected on a low-RAM device where the app is *actually* running `'tiny'` at runtime (`LlmService._resolveSelectedModel` already correctly calls `recommendedModelFor`). This task fixes both hardcoded points to use the same RAM-based recommendation Settings already computes elsewhere (`_recommendedModelId`, via `recommendedModelFor(ramGb)`).

- [ ] **Step 1: Update the failing tests first**

In `test/core/models/model_catalog_test.dart`, replace the whole file:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/models/model_catalog.dart';

void main() {
  group('Model catalog', () {
    test('has exactly three entries: tiny, e2b, and e4b', () {
      expect(kModelCatalog.length, 3);
      expect(kModelCatalog.map((m) => m.id), containsAll(['tiny', 'e2b', 'e4b']));
    });

    test('downloadUrl builds the correct Hugging Face resolve URL', () {
      final e2b = modelById('e2b');
      expect(
        e2b.downloadUrl,
        'https://huggingface.co/${e2b.huggingFaceRepo}/resolve/${e2b.revision}/${e2b.filename}',
      );
    });

    test('modelById returns the matching entry', () {
      expect(modelById('e4b').id, 'e4b');
      expect(modelById('tiny').id, 'tiny');
    });

    test('modelById falls back to the first entry for an unknown id', () {
      expect(modelById('nonexistent').id, kModelCatalog.first.id);
    });

    test('recommendedModelFor picks tiny below the e2b RAM threshold', () {
      expect(recommendedModelFor(2.0).id, 'tiny');
      expect(recommendedModelFor(3.9).id, 'tiny');
    });

    test('recommendedModelFor picks e2b between the e2b and e4b RAM thresholds', () {
      expect(recommendedModelFor(4.0).id, 'e2b');
      expect(recommendedModelFor(5.9).id, 'e2b');
    });

    test('recommendedModelFor picks e4b at or above its RAM threshold', () {
      expect(recommendedModelFor(6.0).id, 'e4b');
      expect(recommendedModelFor(12.0).id, 'e4b');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/models/model_catalog_test.dart`
Expected: FAIL — `kModelCatalog.length` is currently 2, and `modelById('tiny')` currently falls back to `kModelCatalog.first` (`'e2b'`), not a real `'tiny'` entry.

- [ ] **Step 3: Update `model_catalog.dart`**

Replace the catalog doc comment and list — replace:

```dart
/// The fixed, curated set of models users can download. Sizes verified
/// against the real Hugging Face files as of 2026-07-05 (Q4_K_M
/// quantizations from unsloth's Gemma 4 GGUF mirrors — Google's own
/// official repos are gated behind Hugging Face auth + license
/// acceptance, which isn't feasible for an anonymous in-app download).
const List<ModelInfo> kModelCatalog = [
  ModelInfo(
    id: 'e2b',
    displayName: 'Gemma 4 E2B (Lighter)',
    description: 'Recommended for devices with <6GB RAM',
    huggingFaceRepo: 'unsloth/gemma-4-E2B-it-GGUF',
    filename: 'gemma-4-E2B-it-Q4_K_M.gguf',
    revision: 'ecc8b33b2c50598815e4b0f7cea6088e3ae7adb8',
    sizeBytes: 3106736256,
  ),
  ModelInfo(
    id: 'e4b',
    displayName: 'Gemma 4 E4B (Standard)',
    description: 'Recommended for devices with ≥6GB RAM',
    huggingFaceRepo: 'unsloth/gemma-4-E4B-it-GGUF',
    filename: 'gemma-4-E4B-it-Q4_K_M.gguf',
    revision: 'e1d90e5fb9f61d8dc71ef016580784a054e5c787',
    sizeBytes: 4977169568,
    recommendedAboveRamGb: 6.0,
  ),
];
```

with:

```dart
/// The fixed, curated set of models users can download. Sizes verified
/// against the real Hugging Face files (Q4_K_M quantizations from
/// unsloth's Gemma 4 GGUF mirrors for e2b/e4b, as of 2026-07-05; Qwen's own
/// official GGUF repo for the tiny tier, as of 2026-07-09 — Google's own
/// Gemma repos are gated behind Hugging Face auth + license acceptance,
/// which isn't feasible for an anonymous in-app download; Qwen's
/// Apache-2.0 official repo has no such gating). Ordered lightest-first —
/// [recommendedModelFor] relies on the first entry being the correct
/// fallback for devices below every other entry's threshold.
const List<ModelInfo> kModelCatalog = [
  ModelInfo(
    id: 'tiny',
    displayName: 'Qwen 2.5 0.5B (Tiniest)',
    description: 'For very low-RAM devices (<4GB) — shorter, simpler answers',
    huggingFaceRepo: 'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
    filename: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
    revision: '9217f5db79a29953eb74d5343926648285ec7e67',
    sizeBytes: 491400032,
  ),
  ModelInfo(
    id: 'e2b',
    displayName: 'Gemma 4 E2B (Lighter)',
    description: 'Recommended for devices with 4-6GB RAM',
    huggingFaceRepo: 'unsloth/gemma-4-E2B-it-GGUF',
    filename: 'gemma-4-E2B-it-Q4_K_M.gguf',
    revision: 'ecc8b33b2c50598815e4b0f7cea6088e3ae7adb8',
    sizeBytes: 3106736256,
    recommendedAboveRamGb: 4.0,
  ),
  ModelInfo(
    id: 'e4b',
    displayName: 'Gemma 4 E4B (Standard)',
    description: 'Recommended for devices with ≥6GB RAM',
    huggingFaceRepo: 'unsloth/gemma-4-E4B-it-GGUF',
    filename: 'gemma-4-E4B-it-Q4_K_M.gguf',
    revision: 'e1d90e5fb9f61d8dc71ef016580784a054e5c787',
    sizeBytes: 4977169568,
    recommendedAboveRamGb: 6.0,
  ),
];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/models/model_catalog_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Fix `settings_screen.dart`'s hardcoded default**

Replace the field declaration — replace:

```dart
  String _selectedModel = 'e2b';
```

with:

```dart
  String _selectedModel = kModelCatalog.first.id;
```

Replace `_loadSettings`'s model-loading line — replace:

```dart
  Future<void> _loadSettings() async {
    final userRepo = ref.read(userRepositoryProvider);
    final lang = await userRepo.getEngagementValue('selected_language') ?? 'English';
    final model = await userRepo.getEngagementValue('selected_llm_model') ?? 'e2b';
```

with:

```dart
  Future<void> _loadSettings() async {
    final userRepo = ref.read(userRepositoryProvider);
    final defaultModelId = recommendedModelFor(ref.read(llmServiceProvider).detectDeviceRamGb()).id;
    final lang = await userRepo.getEngagementValue('selected_language') ?? 'English';
    final model = await userRepo.getEngagementValue('selected_llm_model') ?? defaultModelId;
```

- [ ] **Step 6: Run the full suite and analyze**

Run: `flutter analyze && flutter test`
Expected: `flutter analyze`: No issues found. `flutter test`: PASS (all tests) — there is no existing widget test asserting `_selectedModel`'s initial value or exercising `_loadSettings`'s fallback branch specifically (confirm with `grep -n "_selectedModel\|_loadSettings" test/ -r`); if one exists and asserts the literal string `'e2b'`, update it to assert against `kModelCatalog.first.id` / `recommendedModelFor(...)` instead of a hardcoded string, for the same reason this task exists.

- [ ] **Step 7: Commit**

```bash
git add lib/core/models/model_catalog.dart lib/presentation/screens/settings_screen.dart test/core/models/model_catalog_test.dart
git commit -m "feat(models): add a tiny Qwen2.5-0.5B tier for <4GB RAM devices, fix Settings' hardcoded e2b default"
```

---

### Task 8: Rebuild + release `kb-v1.2.0`, update `kb_catalog.dart`

This is an **operational task**, not a code-authoring one — the code for it already exists (Tasks 5 and 6 changed `tool/build_kb.dart`; the CI workflow at `.github/workflows/build-kb-on-tag.yml` needs no changes, it already runs `tool/build_kb.dart` generically via `tool/build_kb_runner.dart`). This mirrors the prior round's Task 8 exactly.

**Files:**
- Modify: `lib/core/models/kb_catalog.dart`
- Modify: `test/core/models/kb_catalog_test.dart`
- Modify: `Tracker.md`

- [ ] **Step 1: Verify location before any git operation**

```bash
pwd && git rev-parse --show-toplevel && git branch --show-current
```

Expected: on the branch/worktree this plan's tasks were committed to, matching `git log --oneline -1` against the last commit from Task 7.

- [ ] **Step 2: Build locally first and verify int8 retrieval quality empirically before spending a real CI cycle**

The design doc's assumption A2 (int8 quantization retains retrieval quality) is carried over from published third-party benchmarks on other models — not yet verified against this app's actual BGE-small-en-v1.5 embeddings on this actual corpus. Mirror the prior round's discipline (which caught the mock-embeddings bug this same way): build a real `kb.db` locally before tagging anything, with `LD_LIBRARY_PATH` set for onnxruntime's native `.so` (see `.github/workflows/build-kb-on-tag.yml` for how CI resolves this path):

```bash
flutter test tool/build_kb_runner.dart --timeout=none \
  --dart-define=KB_OUTPUT=/tmp/kb_verify_int8.db --dart-define=KB_VERSION=1.2.0-local-verify
```

Once it completes, spot-check retrieval quality with a small script or `sqlite3` queries: pick 2-3 known verses/hadiths with an obvious topical relationship (e.g. two patience-themed passages) and 1-2 clearly unrelated ones, compute their int8 dot products against a real query embedding (mirroring `RagRepository._dotProductInt8`'s exact integer accumulation, not a float approximation), and confirm the related pair still scores meaningfully higher than the unrelated pair — the same kind of before/after gap the prior round measured for the mock-vs-real-embeddings fix (0.80 vs 0.60 cosine similarity), adapted to integer dot products. If the gap has collapsed compared to what float32 cosine similarity would show for the same pairs, stop and investigate the quantization scheme (Task 6) before proceeding — do not tag and ship on an unverified assumption.

- [ ] **Step 3: Tag and push `kb-v1.2.0`**

```bash
git tag -a kb-v1.2.0 -m "kb-v1.2.0: int8-quantized embeddings + dictionary-encoded BM25 postings"
git push origin kb-v1.2.0
```

- [ ] **Step 4: Poll the GitHub Actions run to completion**

```bash
curl -s "https://api.github.com/repos/gr0-o-0t/learn-quran/actions/runs?event=push&per_page=3"
```

Poll (with a reasonable wait between checks — this build embeds every doc's vector at build time, same as the kb-v1.1.0 build, and took on the order of an hour or more on GitHub's runners) until `status` is `completed`. If `conclusion` is `failure`, diagnose via job steps/check-run annotations before attempting any fix (per systematic-debugging discipline) — do not guess. **Be aware of GitHub's unauthenticated API rate limit (60 requests/hour per IP)** — space out checks, and if rate-limited, check `curl -s "https://api.github.com/rate_limit"` for the reset time rather than retrying immediately.

- [ ] **Step 5: Verify the release and fetch real values**

```bash
curl -s "https://api.github.com/repos/gr0-o-0t/learn-quran/releases/tags/kb-v1.2.0"
curl -sL "https://github.com/gr0-o-0t/learn-quran/releases/download/kb-v1.2.0/kb.db.sha256"
curl -sL "https://github.com/gr0-o-0t/learn-quran/releases/download/kb-v1.2.0/kb.db.size"
```

Record the exact sha256 and size — do not approximate.

- [ ] **Step 6: Update `kb_catalog.dart` with the real values**

Update `lib/core/models/kb_catalog.dart`'s `kCurrentKb` — bump `version` to `'1.2.0'`, `sizeBytes` and `sha256` to the exact values fetched in Step 5, and update the doc comment to describe this release (int8-quantized embeddings + dictionary-encoded BM25 — expect the file to be noticeably smaller than kb-v1.1.0's 536846336 bytes, but confirm the real number rather than assuming).

- [ ] **Step 7: Update `kb_catalog_test.dart`**

Update the hardcoded `sizeBytes`/`sha256` expectations in `test/core/models/kb_catalog_test.dart` to match Step 6's real values.

- [ ] **Step 8: Run the full suite, commit, push**

```bash
flutter analyze && flutter test
git add lib/core/models/kb_catalog.dart test/core/models/kb_catalog_test.dart
git commit -m "chore(kb): pin real kb-v1.2.0 release values in kb_catalog.dart"
git push
```

- [ ] **Step 9: Update `Tracker.md`**

Add a new Phase entry documenting this round (drop HyDE draft, on-device reranker, int8 quantization, BM25 dictionary encoding, tiny LLM tier, the `OrtRuntime` fix, and the Settings default-selection bug found along the way), matching the style of the existing Phase 13 entry. Commit and push.

```bash
git add Tracker.md
git commit -m "docs: record Phase 14 (mobile RAG optimization + kb-v1.2.0) in Tracker.md"
git push
```
