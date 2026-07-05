# RAG Hybrid Retrieval, Tafsir Chunking & Generate-Retrieve-Refine — Design

## Problem

Three related gaps in the current RAG pipeline (`rag_repository.dart`,
`embedding_service.dart`, `llm_service.dart`), surfaced while investigating
why the Q&A screen was consistently declining to answer:

1. **Tafsir truncation.** Each tafsir entry (one row per ayah) is embedded
   whole, but `EmbeddingService` truncates tokenization to 256 tokens. Long
   Ibn Kathir commentary silently loses everything past its first ~256
   tokens *for retrieval-matching purposes* (the full text is still shown
   once retrieved — only the embedding is blind to the rest).
2. **Retrieval is brute-force and re-reads the whole table every query.**
   `RagRepository.search()` runs `SELECT rowid, embedding FROM
   vec_knowledge_base` (all ~27K rows) on every call, parses each BLOB, and
   does a scalar dot product — reported as too slow on a phone. `sqlite-vec`
   was already confirmed non-functional in this build environment (Tracker.md
   Task 12.4, deferred) so no native ANN index is available.
3. **Retrieval is single-shot on the raw question**, purely semantic
   (no lexical/keyword signal), with no re-ranking and no query refinement.

## Understanding Summary

- **What**: rework the RAG pipeline — chunk long tafsir entries, add a
  precomputed BM25 keyword index alongside the existing embedding index,
  fuse both via Reciprocal Rank Fusion, and switch from
  "retrieve-then-generate" to "draft-then-retrieve-then-refine" (the LLM
  drafts a short hypothetical answer from its own knowledge first, that
  draft is used as the retrieval query — the HyDE technique — then the
  final answer is generated grounded in the real retrieved references).
- **Why**: fix silent tafsir truncation, make retrieval fast enough for a
  phone, and improve retrieval quality (a raw short question often
  embeds/matches worse than a fuller hypothetical answer).
- **Who**: the offline Q&A screen's real (non-mock) LLM path.
- **Key constraints**: must stay fully offline (query "rewriting" is the
  local LLM itself, never an external service); no new on-device ML model
  (no separate cross-encoder re-ranker — re-ranking here means RRF fusion
  of BM25 + embedding signals); `sqlite-vec` is not being retried this
  round.
- **Non-goals**: conversation-history-aware retrieval; changing verse/hadith
  granularity (only tafsir needs chunking); a persisted/on-device-built BM25
  index (it's precomputed at KB-build time instead).

## Assumptions

- **A1**: The hidden draft answer is retrieval fuel only, never a fallback
  answer. If the draft generation fails, retrieval falls back to the raw
  question. If retrieval (even hybrid) finds nothing sufficiently relevant,
  the refine pass still carries the existing decline-if-insufficient
  instruction — the zero-hallucination guarantee is unchanged either way.
- **A2**: Each retrieval method (embedding, BM25) returns its own top-20;
  RRF fuses them; the final context/citation set is the fused top-5 (up
  from today's top-3).
- **A3**: This requires a new KB version (`kb-v1.1.0`, a schema change) and
  a rebuild+release via the existing `tool/build_kb.dart` / GitHub Actions
  pipeline, as already done twice this project.
- **A4**: Performance target — hybrid retrieval should complete in well
  under a second on a mid/low-range Android phone. This is a design goal;
  there is no physical device in this dev environment to benchmark against,
  so it needs on-device verification after implementation.

## Decision Log

| Decision | Chosen | Alternative considered | Why |
|---|---|---|---|
| Draft visibility | Hidden entirely; only the final refined answer is shown | Stream draft, then replace with refined answer | Faster perceived first response, but would briefly show an uncited/unverified claim — conflicts with the zero-hallucination intent |
| Draft length | Short, ~100-150 tokens (HyDE-style) | Full 512-token draft | The draft is discarded after retrieval; a full-length draft would roughly double generation latency for no retained value |
| Retrieval speed strategy | Optimize the pure-Dart path (in-memory embedding cache, SIMD dot products, BM25 pre-filtering) | Retry root-causing `sqlite-vec`/`vec0` | Already documented as non-functional here (Task 12.4); open-ended native-build investigation with no guaranteed payoff |
| Tafsir chunking | Sentence-grouped, ~200 tokens/chunk, no overlap, using real tokenizer counts | Fixed-token sliding window with overlap | Respects sentence boundaries; no overlap needed since every chunk already carries its parent's surah:ayah citation |
| BM25 index storage | Precomputed in `kb.db` at build time (new tables) | Built on-device at app startup | Zero runtime index-build cost; the KB rebuild is already happening for chunking, so bundling BM25 data into it is free |
| Final top-k | 5 (up from 3) | Keep at 3 | Hybrid retrieval + chunking should raise average relevance; a slightly larger context set is affordable within the 4096-token window |
| Re-ranking mechanism | Reciprocal Rank Fusion of BM25 + embedding ranked lists | A separate cross-encoder re-ranker model | RRF needs no new on-device ML asset/download and no score-scale normalization between BM25 and dot-product scores |
| Doc-id scheme | Extend the existing verse/hadith/tafsir rowid-offset scheme to also cover tafsir chunks; one id space shared by embeddings, BM25, and citation lookups | Separate id spaces per retrieval method with a mapping table | Avoids an unnecessary mapping layer — fusion becomes a plain join on one integer |
| `tafsirs` table | Left untouched; new `tafsir_chunks` table added for RAG only | Replace `tafsirs` with chunked rows | `QuranRepository.getTafsirForVerse()` reads full, unchunked content for display — must not be split |
| Old-KB compatibility | BM25 sub-search wrapped in try/catch; missing tables silently fall back to embedding-only | Detect schema mismatch up front and block Q&A until KB update | Simpler; embedding-only search already works against both old and new `kb.db` shapes, so there's nothing to block |
| Mock/no-engine path | Left completely unchanged (single-pass, no draft) | Apply the two-pass flow universally | The two-pass flow only has value with a real model; forcing it through the mock path adds risk for no benefit and would touch already-covered tests |
| Citation-building logic | Extracted to `RagRepository.citationFor()`, a pure function | Keep duplicated in `qa_agent_screen.dart` and re-derive in `LlmService` | Single source of truth for surah-name lookups and title formatting; independently unit-testable |

## Final Design

### Architecture & data flow

```
question
  → LLM draft pass (short, ~100-150 tokens, own knowledge, no RAG context)
  → hybrid retrieval query = draft text (HyDE) — falls back to raw question if the draft pass fails
      ├─ embedding search: embed(draft) → in-memory SIMD cosine scan → top-20
      └─ BM25 search: tokenize(draft) → indexed lexical lookup → top-20
  → Reciprocal Rank Fusion (k=60) → fused top-5
  → LLM refine pass (full 512 tokens, today's citation-required system prompt + fused context, original question) → final cited answer (streamed)
```

The **original question**, not the draft, is what the refine pass answers
and what the user sees asked back to them. The draft only steers retrieval.

### Schema changes (new KB version, `kb-v1.1.0`)

- **`TafsirChunks`**: `id, tafsirId (FK), surahNumber, ayahNumber, author, chunkIndex, contentEnglish`. The existing `Tafsirs` table is untouched.
- **Doc-id space** (extends the existing scheme): verses use raw `id`; hadiths use `id + 100000`; tafsir chunks use `id + 200000` (`vec_knowledge_base` now holds one row per chunk here, not per ayah-tafsir).
- **`Bm25Postings(term, docId, termFrequency)`**, indexed on `term`.
- **`Bm25DocStats(docId PRIMARY KEY, docLength)`**.
- Two new `KbMeta` keys: `bm25_doc_count`, `bm25_avg_doc_length`.
- No in-place data migration: `kb.db` is always either empty (fresh schema via `onCreate`) or a wholesale, hash-verified download at one pinned version — never altered incrementally.

### Chunking algorithm (`tool/build_kb.dart`, build time only)

Split `contentEnglish` on sentence boundaries (`. ! ?` + whitespace), then
greedily group sentences into a chunk, measuring real token count via the
same `BertTokenizer` already used for embeddings — stop before a chunk
would exceed ~200 tokens. A single sentence that alone exceeds 200 tokens
becomes its own (slightly over-budget) chunk rather than being split
mid-sentence. Entries that already fit in one chunk produce exactly one row
(no behavior change for the majority of tafsir entries).

### BM25 index (build time + query time)

Built once at KB-build time over the unified doc-id space (verses, hadiths,
tafsir chunks together), using a single shared tokenizer function
(lowercase, strip punctuation, split on whitespace) used identically by
`tool/build_kb.dart` at index time and the app's `Bm25Index` at query time,
so the two can never drift apart.

At query time: tokenize the query, dedupe terms, one indexed `WHERE term =
?` lookup per term (typically 3-8 lookups for a short question), one batched
`WHERE docId IN (...)` lookup for doc lengths (avoids N+1), score with
standard BM25 (k1=1.2, b=0.75) using the `KbMeta`-stored corpus stats, return
top-20.

### Embedding search (rewritten `RagRepository`)

On first use, load `vec_knowledge_base` once into a flat `Float32List`
(docCount × 384, contiguous) plus a parallel doc-id list — replacing the
current per-query full-table SQL re-read, which is the dominant cost today.
Dot products use `Float32x4` SIMD (384 divides evenly into 96 lanes).
Scores are fully sorted and the top-20 taken; with the SQL round-trip gone,
sorting ~30K doubles doesn't need heap-based top-k. This cache is naturally
rebuilt whenever the KB is re-downloaded, since that already produces a
fresh `RagRepository` via existing provider-invalidation wiring.

### Fusion

Reciprocal Rank Fusion: `score(doc) = Σ 1/(60 + rank)` summed across
whichever of the two ranked lists contain it. A doc found by only one
method still scores from that list alone. Fused top-5 becomes the final
context/citation set.

### LLM orchestration (`llm_service.dart`)

New method:

```dart
Stream<String> generateGroundedResponseStream(
  String question, {
  required RagRepository ragRepository,
  void Function(List<RagSearchResult>)? onRetrieved,
})
```

Runs the draft pass (short system prompt, no RAG context, `maxTokens: 150`),
falls back to the raw question on draft failure, calls
`ragRepository.search(retrievalQuery, limit: 5)`, invokes `onRetrieved` so
the UI can build citations immediately, then runs the existing full refine
pass and streams its output. The mock/no-engine path (`_generateMockResponse`)
is untouched — single-pass, no draft, retrieval on the raw question, exactly
as today.

### Shared citation logic

`RagRepository.citationFor(RagSearchResult) -> RagCitation {title, text}`
replaces the inline title/text construction currently duplicated in
`qa_agent_screen.dart`, used by both the new `LlmService` method (to build
`ragContext`) and the UI (to build citation chips).

### `qa_agent_screen.dart` changes

`_sendMessage` calls `generateGroundedResponseStream` instead of
`generateResponseStream` plus its own inline RAG call; citations populate
via the `onRetrieved` callback. The streaming/`setState` loop is otherwise
unchanged.

### Error handling summary

| Failure | Behavior |
|---|---|
| Draft generation fails/times out | Retrieval falls back to the raw question |
| BM25 query hits a missing table (old `kb.db`, app updated first) | Caught; falls back to embedding-only results |
| No relevant results (even hybrid) | Refine pass still carries the decline-if-insufficient instruction |
| No engine loaded (mock path) | Completely unchanged: single-pass, no draft |

### Testing strategy

- **Chunking**: `chunkText(text, maxTokens, {countTokens})` as a pure,
  extractable function — tests inject a cheap word-count fake to verify
  boundary/grouping logic independent of the real tokenizer.
- **`Bm25Index`**: unit tests against a seeded in-memory test KB (same
  `.forTesting()` pattern as the download services), verifying known-term
  retrieval and hand-computed BM25 ranking on a small fixture.
- **Hybrid `RagRepository.search()`**: seeded fixture KB with both
  embeddings and BM25 data; verify RRF fusion order against hand-calculated
  expectations, including a doc found by only one method.
- **`LlmService` orchestration**: real llama.cpp inference can't run in this
  environment, so a minimal injectable "generate" seam (same DI pattern as
  the download-service rewrites) tests control flow only — draft-failure
  fallback, `onRetrieved` firing with the right results, mock path proven
  untouched.
- **`citationFor()`**: plain unit tests per source type including surah-name
  lookup correctness.

## Implementation Handoff

Ready to turn this into an implementation plan (task breakdown, file-by-file
changes, TDD steps) once confirmed.
