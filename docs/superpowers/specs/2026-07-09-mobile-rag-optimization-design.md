# Mobile RAG Optimization (Post-Hybrid-Retrieval) — Design

## Problem

The hybrid RAG retrieval redesign (kb-v1.1.0, `v1.3.0`) fixed the original
"always declines" bug and the mock-embeddings root cause, but on real phones
— particularly the stated floor of **budget Android, 3-4GB RAM** — the
pipeline is still:

- **Too heavy**: slow responses, RAM pressure/lag/crashes, a large
  512MB `kb.db` + a 3.1-5GB LLM model file to download and store, and
  battery drain.
- **Still inaccurate**: wrong/irrelevant citations, and false "no local
  source" declines. Both point at retrieval quality, not
  hallucination/tone/citation-formatting (already solid per the prior
  round's final review).

## Understanding Summary

- **What**: a second optimization pass over the same pipeline
  (`rag_repository.dart`, `bm25_index.dart`, `embedding_service.dart`,
  `llm_service.dart`, `tool/build_kb.dart`), plus a new, much smaller LLM
  tier specifically for the low-RAM floor.
- **Why**: the prior redesign fixed correctness (real embeddings, hybrid
  search) but not the resource footprint or the residual retrieval-accuracy
  gap — both still block real use on budget devices.
- **Who**: the same offline Q&A screen, now explicitly targeting a 3-4GB RAM
  Android floor (more aggressive than the industry norm — Google's own AI
  Edge RAG SDK targets flagship phones only).
- **Key constraints**: a new kb.db rebuild is acceptable; the existing
  two-LLM-pass (draft+refine) architecture is open for reconsideration;
  `sqlite-vec` remains out of scope (confirmed still broken for mobile
  industry-wide, not project-specific).
- **Non-goals**: fixing hallucination/tone/citation formatting (not
  reported as broken); corpus growth beyond the current ~77K docs; web
  platform (already out of scope for this app).

## Assumptions

- **A1**: At ~77K vectors, brute-force SIMD embedding search is within the
  generally-accepted "fine without ANN" range (typical crossover cited at
  100K-1M vectors) — this is an extrapolation from desktop/server
  benchmarks, not a phone-SoC-specific measurement, but no ANN migration
  (HNSW/ObjectBox/sqlite-vec) is being adopted this round on that basis.
- **A2**: int8 quantization of the stored embeddings retains ~90-100% of
  retrieval quality per published third-party benchmarks (HF, Qdrant,
  MongoDB Atlas) — assumed to transfer to BGE-small-en-v1.5, not
  independently re-benchmarked against this exact corpus.
- **A3**: Whether int8 vectors can be kept in memory and dot-producted via a
  plain scalar integer loop fast enough (to also cut runtime RAM, not just
  disk/download size) is **not yet validated** — Dart has no native int8
  SIMD type. This needs an empirical timing check during implementation; if
  too slow, fall back to dequantizing to the existing `Float32x4` cache at
  load time (loses the RAM win, keeps the storage/download win).
- **A4**: BM25 postings (3.5M rows) are assumed, but not measured, to be a
  large — possibly the largest — contributor to `kb.db`'s 512MB, based on
  row-count back-of-envelope estimation, not a real `dbstat` measurement.
  Dictionary-encoding is proposed regardless since it's a standard,
  low-risk technique independent of exactly how much it saves.
- **A5**: The new tiny LLM tier (Qwen2.5-0.5B-Instruct) is a real quality
  trade-off, not a hidden regression — it exists so the app is usable at
  all on the 3-4GB floor, and Settings' UI must say so plainly.
- **A6**: Extractive context trimming (MobileRAG-style) is deferred as a
  follow-up, not built this round — the context is already small (~1,000
  tokens for 5 chunks) once the draft pass is removed and reranking
  improves relevance, so the marginal benefit is unclear until measured
  against this app's actual (already-small) context size.

## Decision Log

| Decision | Alternatives considered | Why chosen |
|---|---|---|
| Drop the HyDE draft pass entirely (not flagged/kept) | Keep draft but optimize it; replace with cheaper non-LLM query expansion | Research: HyDE costs 25-60% latency increase for small local LLMs. A bad/hallucinated draft can misdirect retrieval — plausible single root cause for both "heavy" and "wrong citations." Simplest fix: one fewer LLM call. |
| int8-quantize embedding vectors in the kb.db rebuild | Keep float32; binary quantization (32x smaller); switch embedding model entirely | ~4x size win, ~90-100% quality retention (A2). Binary quantization's larger accuracy variance too risky given the existing accuracy complaint. Model swap not needed — the model isn't the identified bottleneck. |
| Target keeping int8 in the runtime cache with scalar-int dot products (not just on-disk) | Dequantize to float32 cache at load time (simpler, reuses existing SIMD code) | Also cuts runtime RAM (~112MB→~30MB), not just download size — but flagged as needing empirical validation (A3), with float32-cache dequantization as the fallback. |
| Dictionary-encode BM25 postings (new `Bm25Terms` table + `termId`) | Leave raw term-per-row; prune rare terms instead | Standard, low-risk inverted-index compression; likely (A4) the single largest kb.db size lever given 3.5M rows. |
| Add an on-device cross-encoder reranker: `Xenova/ms-marco-MiniLM-L-6-v2`, int8 ONNX (~23MB) | `bge-reranker-base`/`v2-m3` (ruled out: 278-568M params, SentencePiece tokenizer — new dependency, 10-25x larger); ColBERT-style late interaction (ruled out: no mobile deployment precedent found — "unsettled" per research); no reranker (Approach C) | Strongest evidenced lever specifically for "wrong/irrelevant citations." Reuses the app's existing WordPiece tokenizer infrastructure — no new tokenizer dependency. |
| Reranker failure → skip reranking, fall back to plain RRF order | Mock reranker scores, mirroring `EmbeddingService`'s mock-embedding pattern | RRF order is a real, working fallback. A fake reranker score would be actively misleading, unlike a mock embedding vector (which at least behaves consistently). |
| Defer extractive context trimming (A6) | Implement now, reusing the new reranker to score sentences | Context is already small post-draft-removal; avoid speculative complexity (YAGNI) until measured. |
| Add a third LLM tier: `Qwen/Qwen2.5-0.5B-Instruct-GGUF` Q4_K_M (~491MB) as the new floor for <4GB RAM | `SmolLM2-360M-Instruct` (271MB, credible smaller fallback); `Llama-3.2-1B-Instruct` (808MB, more license friction); `Gemma-3-270M-it` (ruled out: weak factuality per its own model card, positioned as a fine-tuning base, not a generalist) | Cleanest license (Apache-2.0), best-documented instruction-following claims at this size, order-of-magnitude smaller than the current floor (Gemma E2B, 3.1GB) which was consuming nearly all RAM on the stated device floor. |
| Frame the tiny tier as an explicit "usable degraded mode" in Settings copy | Hide the trade-off; refuse to ship a lower-quality tier | Transparency; goal is "works without crashing" on the floor device, not matching e2b's answer quality. |
| Keep brute-force SIMD embedding search (no ANN adoption) | ObjectBox 4.0+ (first-class Flutter HNSW); `local_hnsw` (pure Dart); retry `sqlite-vec` | Per A1, current scale doesn't need it; `sqlite-vec` confirmed still broken for mobile industry-wide. Flagged as a future escape hatch if corpus scale grows substantially. |
| kb.db `schemaVersion` bump 2→3 | — | Same pattern as the prior bump; the existing `openKnowledgeBaseDatabaseSafely` recovery path already handles this with no new migration code. |

## Final Design

### 1. Retrieval pipeline architecture

Per-query flow changes from **draft LLM call → retrieve on draft →
embedding+BM25 search → RRF fuse → top-5 → refine LLM call** to:

**retrieve directly on the raw question → embedding search (top-20) + BM25
search (top-20) → RRF fuse (wider candidate set, ~15-20) → cross-encoder
reranks the fused candidates → top-5 by rerank score → single LLM call (no
draft) using the original question.**

- `LlmService.generateGroundedResponseStream` becomes a thinner wrapper:
  retrieve, then call the existing single-pass `generateResponseStream`. The
  HyDE-specific code (`_draftSystemPrompt`, the draft `_chat` call) is
  deleted, not kept behind a flag.
- Reranking is a new stage inside `RagRepository.search()`, after RRF
  fusion and before truncating to the final `limit` (5) — it needs to see
  more candidates than the final cut to be useful.
- Every existing public interface (`RagRepository.search`, `citationFor`,
  the UI's `onRetrieved` callback, `RagSearchResult`) stays stable — the
  reranker is an internal stage, not new public surface.

### 2. KB rebuild (kb-v1.2.0, schemaVersion 2→3)

**int8-quantized embedding vectors**: `tool/build_kb.dart` scales each
computed float32 embedding to int8 before writing to
`vec_knowledge_base` (BGE embeddings are L2-normalized and bounded, so a
fixed or per-vector scale works). `_ensureEmbeddingCache` reads int8 and
targets keeping the runtime cache in int8 with scalar-int dot products
(A3) — if that proves too slow in practice, dequantize to the existing
`Float32x4` cache at load time instead (storage/download win preserved
either way).

**Dictionary-encoded BM25 postings**: new `Bm25Terms` table (`termId` PK,
unique `term` TEXT). `Bm25Postings.term` (TEXT) becomes
`Bm25Postings.termId` (INTEGER). `tool/build_kb.dart` builds the term
dictionary once at build time; `Bm25Index.search` resolves query tokens to
`termId`s first, then queries postings by `termId`. Same query shape,
smaller index (A4).

Both changes are internal to `tool/build_kb.dart`, `Bm25Index`, and
`RagRepository`'s cache loading — no change to `RagRepository.search()`'s
public behavior, RRF, or citations.

### 3. On-device reranker

New `RerankerService` (mirrors `EmbeddingService`'s shape: lazy ONNX
session init, `Future<double> score(String query, String passageText)`).
Model: `Xenova/ms-marco-MiniLM-L-6-v2`, int8 ONNX (~23MB), bundled with its
own `vocab.txt` (reuses the existing `bert_tokenizer` package — a
cross-encoder joins query+passage into one sequence with
`[CLS] query [SEP] passage [SEP]` and `token_type_ids`, and reads a single
output logit — no CLS-pooling step needed, simpler than the embedding
model's forward pass).

Integrated into `RagRepository.search()` per Section 1. On any reranker
load/scoring failure, skip reranking and fall back to plain RRF order —
never a fake/mock score (see Decision Log).

### 4. Extractive context trimming — deferred

Not built this round (A6). If revisited later: reuse the reranker to score
individual sentences within a selected chunk against the query, keep only
the top-scoring sentences, drop the rest before `LlmService._buildRagContext`
builds the prompt. No new model needed if/when this happens.

### 5. New tiny LLM tier

Add a third `ModelInfo` entry to `lib/core/models/model_catalog.dart`:
`Qwen/Qwen2.5-0.5B-Instruct-GGUF`, Q4_K_M (~491MB), Apache-2.0. Becomes the
new fallback/floor tier — `recommendedModelFor`'s existing "fall back to
the first entry" logic makes this the new default for devices below e2b's
threshold. e2b's existing `recommendedAboveRamGb` gets a real lower bound
(e.g. 4.0) instead of being the implicit floor.

Everything downstream (`LlmService`, `generateResponseStream`, the
grounded-QA flow) is unaffected by design — none of it hardcodes a specific
model tier. Settings' model picker gets a third row for free (iterates
`kModelCatalog`). Settings' description text for this tier must state the
quality trade-off plainly (A5) — e.g. "Lightest — for very low-RAM devices;
shorter, simpler answers."

### Testing strategy

- `RerankerService`: unit tests with a `forceMock`-style seam (mirroring
  `EmbeddingService`) so tests don't need a real ONNX model file; a
  real-model smoke test mirroring how `EmbeddingService`'s real-model path
  is (or isn't) currently tested.
- `RagRepository.search()`: existing hybrid-search tests extended to cover
  reranking reordering a case where RRF's raw order would've been wrong,
  and the reranker-failure fallback path (skip reranking, RRF order
  preserved).
- `Bm25Index`: extended for the term-dictionary lookup (query term → termId
  → postings), including "term not in dictionary" (no matches, not a
  throw).
- `tool/build_kb.dart`: int8 quantization round-trip (embed → quantize →
  dequantize is within an acceptable error tolerance of the original
  float32 vector) as a build-time sanity check, similar in spirit to the
  existing embedding-fallback logging.
- `model_catalog.dart`: extend the existing `recommendedModelFor` tests for
  the new three-tier threshold boundaries.
- No physical low-RAM device is available in this dev environment (same
  caveat as the prior round's A4) — real-device validation of the "no
  longer crashes on 3-4GB RAM" goal has to happen outside this repo's test
  suite.
