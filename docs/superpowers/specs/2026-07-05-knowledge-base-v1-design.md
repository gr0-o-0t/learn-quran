# Knowledge Base v1 (Content + Real Embeddings) — Design

> **Post-implementation update:** the "bundled by default" decision below
> (and the matching `Rules.md` exception) was reversed after actually
> trying to push the built `kb.db` — it's 247MB, and GitHub hard-rejects
> any git-tracked file over 100MB, no exceptions. Git history was rewritten
> to strip the blob, and the knowledge base is now **download-required**,
> exactly like the LLM model already works: the app ships with no
> Quran/Hadith/Tafsir content out of the box; `KnowledgeBaseDatabase` opens
> an empty schema until the user downloads `kb.db` from Settings, and
> `QuranReaderScreen` shows a setup prompt (mirroring the AI-setup one)
> until then. Left the original reasoning below for the record — it was a
> reasonable call given the "tens of MB, not GBs" size estimate at the
> time, which turned out to be wrong by an order of magnitude.

## Problem

Two related, previously-undiscovered gaps:

1. **The Quran reader itself is broken beyond Al-Fatiha.** `assets/databases/quran_base.db` — bundled as the app's only content — has exactly 7 verses (Al-Fatiha), 1 hadith, and 1 tafsir entry. `SurahDetailScreen`/`JuzDetailScreen`/`QuranRepository` all read straight from this data. Opening any other surah shows an empty list today. This was seed/fixture data from the initial scaffold, never followed up (`Tracker.md` Task 2.3 just says "Completed" with no note that only a placeholder sample was ever added).
2. **RAG search runs correct code over meaningless data.** `EmbeddingService.getEmbedding()` tries to load `assets/models/embedding_model.onnx` — that file doesn't exist (only `.gitkeep`) — so it always falls back to `_generateMockEmbedding()`, a `Random(text.hashCode)`-seeded vector with no semantic relationship to the text. Even with a real ONNX model, `_tokenize()` is `text.codeUnits.map((e) => e % 30000)` — not a real tokenizer. `RagRepository.populateVectorIndex()` also generates these on-device on first launch, which directly violates `Rules.md` §3's "Pre-compiled Index" rule (the rule was already correct; the code violated it).

## Solution

Complete, authentically-sourced Quran/Hadith/Tafsir content plus real precomputed English embeddings, packaged into a versioned, always-read-only `kb.db` — separate from the app's own read-write user-data database — built by a small offline tool and published to GitHub Releases so it can be updated independently of app store releases. The initial version ships bundled as an asset so the app works fully offline from first launch.

### Sources (verified real, not guessed — see Decision Log at the end for the verification trail)

| Content | Languages | Source | Exact identifiers |
|---|---|---|---|
| Quran (6,236 ayat, 114 surahs) | Arabic (Uthmani), English, Bengali | `api.alquran.cloud` | `quran-uthmani`, `en.sahih` (Saheeh International), `bn.bengali` (Muhiuddin Khan) |
| Hadith (Sahih al-Bukhari + Sahih Muslim only) | Arabic, English, Bengali | `fawazahmed0/hadith-api` (Unlicense) | `ara-bukhari`/`eng-bukhari`/`ben-bukhari`, `ara-muslim`/`eng-muslim`/`ben-muslim` |
| Tafsir Ibn Kathir | English, Bengali (no Arabic column, matches existing schema) | `spa5k/tafsir_api` (MIT), sourced from qul.tarteel.ai | `en-tafisr-ibn-kathir`, `bn-tafseer-ibn-e-kaseer` |

Hindi is **dropped from the schema entirely** — no authentic Hindi source exists for Hadith or Tafsir Ibn Kathir (Hindi Quran translation exists but was dropped too, for consistency). AI-translation-on-demand into any language, using the already-wired `LlmService`, with a persistent "AI-translated, may be inaccurate" notice, is a deferred follow-up feature — not part of this work.

### Embedding model

`BAAI/bge-small-en-v1.5` (MIT license), 384-dim, retrieval-tuned. ONNX export: `Xenova/bge-small-en-v1.5/onnx/model_quantized.onnx`, verified real, 34,014,426 bytes. English-only for this pass (Arabic/Bengali text still stored and displayed, just not separately searchable yet — RAG citations are English-only today anyway).

Tokenizer: real WordPiece via the `bert_tokenizer` pub.dev package (pure Dart, zero Flutter dependency, v1.1.1) loading the model's real `vocab.txt` (231,508 bytes, verified) — replaces the current fake char-code tokenizer.

BGE's documented asymmetric convention: passages embed plain; queries get a fixed prefix (`"Represent this sentence for searching relevant passages: "`) before embedding. `EmbeddingService.getEmbedding()` gains an `isQuery` parameter for this.

### `kb.db` schema (new, separate `KnowledgeBaseDatabase`)

Same as today's `Verses`/`Hadiths`/`Tafsirs` tables minus the `hindi_text`/`hindiText`/`contentHindi` columns, plus a `kb_meta` table (`version`, `built_at`, `embedding_model`) so the app can tell what it has. `vec_knowledge_base` moves here too, precomputed at build time — never generated on-device again — always as the plain `(rowid INTEGER PRIMARY KEY, embedding BLOB)` fallback shape (see the `sqlite-vec` finding above), not a real `vec0` virtual table.

Tafsir schema stays `ayah_number` (single column, not a range) — verified against real Ibn Kathir data: the API already returns one entry per ayah, duplicating the same commentary text across grouped ayat (e.g. surah 1 ayahs 6 and 7 share identical text) rather than requiring range logic on our end. The existing `getTafsirForVerse` exact-match query needs no change.

### The build pipeline is not new machinery

`RagRepository.populateVectorIndex()` already does exactly the right thing: create tables → insert content → embed via `EmbeddingService` → insert vectors. It was just being run **on-device, with fake data**. Once `EmbeddingService` is fixed, a small offline tool (`tool/build_kb.dart`) reuses this same logic: fetch real content from the three verified APIs → insert into a fresh `KnowledgeBaseDatabase` file → run the (now-correct) indexing → ship the resulting `kb.db`. Same code, real data, run once by us instead of once per device with garbage.

**Newly discovered, separate pre-existing bug — `sqlite-vec` itself doesn't actually load.** While verifying this pipeline I tested `AppDatabase`'s real `_createVirtualTable()` path directly (`sqlite3.loadSqliteVectorExtension()` → check `pragma_module_list` for `vec0`) in this dev environment: `hasVectorExtension` is `false`, and creating a `vec0` virtual table throws `no such module: vec0`, even though `loadSqliteVectorExtension()` itself reports no error. `Tracker.md` Task 4.1 ("Setup sqlite-vec FFI compilation," marked Completed) apparently never actually verified this loads — the app has been silently running the Dart-side fallback search this whole time. This is a **separate, pre-existing gap**, not something this KB work introduces or needs to fix: `RagRepository.search()` already has a working, already-tested Dart-side dot-product fallback for exactly this case, and for a ~15-20K row corpus that's fast enough. Given this, `kb.db` will be built using the plain-BLOB fallback table shape (not a real `vec0` virtual table) so it's guaranteed to open and search correctly everywhere, rather than depending on a native extension that isn't currently confirmed to work anywhere. Root-causing why `sqlite-vec` doesn't load is worth its own follow-up, out of scope here.

### CI / release pipeline

New `.github/workflows/build-kb-on-tag.yml`, mirroring `build-on-tag.yml`'s conventions (`permissions: contents: write`, `actions/upload-artifact`, `softprops/action-gh-release@v3`). Triggered on `kb-v[0-9]+.[0-9]+.[0-9]+*` tags — distinct prefix from the app's own `v[0-9]+.[0-9]+.[0-9]+*` release tags, no collision. Single Linux job (kb.db is portable data, not compiled native code, so no per-platform build matrix needed): checkout → Flutter setup → `flutter pub get` → run `tool/build_kb.dart` (this is our own build tooling fetching from the internet, not the shipped app — `Rules.md`'s network restriction applies to the app, not to how we build its data) → compute sha256 + exact byte size → publish `kb.db` as a release asset. The logged size/sha256 gets hand-copied into `kb_catalog.dart`, exactly how `model_catalog.dart`'s pinned revision + `sizeBytes` work today.

### App-side architecture

- New `KnowledgeBaseDatabase` (Drift) holds `verses`/`hadiths`/`tafsirs`/`vec_knowledge_base`/`kb_meta`. The app never writes to it.
- `AppDatabase` shrinks to just `UserProgress`/`SalatLogs`/`Conversations`/`Messages`/`UserEngagementState` — a schema version bump, treated as a clean cut (no real users exist on the placeholder content schema today).
- Initial `kb.db` ships as an asset (`assets/databases/kb.db`, replacing `quran_base.db`), copied to app-writable storage on first launch — the same pattern `AppDatabase`'s `_openConnection()` already uses for `quran_base.db` today.
- New `KbDownloadService`, near-identical to `ModelDownloadService`: pinned exact GitHub Release URL + size, HTTP Range resume, idle-timeout stream — the same proven pattern, not reinvented.
- `QuranRepository`/`RagRepository` constructors change from `AppDatabase` to `KnowledgeBaseDatabase`.
- Settings gets a new "Knowledge Base" section mirroring the AI Model section (including the progress-bar theming fix from the model-download work): current version, "Check for updates," download progress, and a prompt to restart the app to apply an update (simpler and safer than hot-swapping a live SQLite connection mid-session).

### `Rules.md` amendment

Add to the "No Unapproved Networks" bullet under §2, mirroring the existing LLM-model exception:

```markdown
Exception: the Quran/Hadith/Tafsir knowledge base and its embeddings may
also be fetched at runtime from a versioned, pinned GitHub Release,
user-initiated, so corrections/expansions don't require a full app-store
release. The initial knowledge base ships bundled as an asset so the app
works fully offline from first launch — only updates are network-fetched.
```

No change needed to §3's "Pre-compiled Index" rule — it was already correct; the code was violating it, and this work fixes the code.

### `Schema.md` amendment

Update §1 (`verses`/`hadiths`/`tafsirs`) to remove the `hindi_text`/`content_hindi` columns, and add a note that these tables plus §3's `vec_knowledge_base` now live in a separate, always-read-only `kb.db` file rather than the same physical database as §2's user-data tables.

## Data flow

```
kb-v1.0.0 tag pushed
  → CI: tool/build_kb.dart fetches Quran/Hadith/Tafsir from verified APIs
      → inserts into fresh KnowledgeBaseDatabase
      → EmbeddingService (real BGE model + real tokenizer) embeds English text
      → populateVectorIndex()-equivalent writes vec_knowledge_base
  → kb.db published as a GitHub Release asset
  → sha256 + size hand-copied into kb_catalog.dart in a follow-up commit

App first launch
  → AppDatabase seeds user-data tables only (no more quran_base.db copy there)
  → KnowledgeBaseDatabase copies bundled assets/databases/kb.db to writable storage
  → Quran reader / RAG both work fully offline immediately

Settings → Knowledge Base → Check for updates
  → KbDownloadService.isDownloaded() / downloadKb() — same Range-resume,
    idle-timeout pattern as ModelDownloadService
  → on success: prompt "Restart to apply update"
```

## Testing

- Tokenizer: real unit tests against the bundled `vocab.txt` with known WordPiece test vectors — fast, no network, no ONNX runtime.
- `EmbeddingService`: mock the `OrtSession` boundary for logic tests (query-prefix applied correctly, normalization, error fallback); one **manual** verification with the real 33MB ONNX model (same approach as the LLM smoke test), not asserted in CI.
- `KnowledgeBaseDatabase` + `QuranRepository`/`RagRepository`: fixture `kb.db` with a handful of real (not fabricated) sample rows — same pattern already used for `ModelDownloadService`/`UserRepository` tests.
- `KbDownloadService`: directly mirrors `ModelDownloadService`'s existing test suite (resume, stall-timeout, exact-size verification).
- `tool/build_kb.dart`: unit-test the transform logic against fixture API JSON (shape-correctness), without hitting the network in CI test runs. The live-fetch + real-embedding run only happens when deliberately cutting a `kb-vX.Y.Z` release.
- CI release job itself: verified by actually cutting a release, not by a meta-test (same as the app's existing release workflow).

## Out of scope (deferred, separate design discussions)

- AI-translation-on-demand Settings feature (the actual answer to the Hindi gap).
- Personalization RAG over the user's own chat/prayer history ("nudge like a teacher").
- All six Hadith books (Bukhari + Muslim only, for now — "the two Sahihs").
- Embedding non-English text.
- Any change to the already-completed LLM inference wiring (`llamadart`).
- Root-causing why `sqlite-vec`/`vec0` doesn't actually load in this environment (newly discovered, pre-existing, unrelated to KB content/embeddings — the app already has a working, tested fallback).

## Decision Log

| Decision | Alternatives considered | Why this one |
|---|---|---|
| Embedding model: BGE-small-en-v1.5 | all-MiniLM-L6-v2 | Retrieval-tuned, not just general similarity; both verified real/licensed via HF API, BGE fits RAG better |
| Tokenizer: `bert_tokenizer` (pub.dev) + real `vocab.txt` | Hand-roll WordPiece | Freshest pub.dev package (published days before this design), pure Dart, zero Flutter dependency |
| Hadith scope: Bukhari + Muslim only | All six books | Bounds corpus size/review effort for v1; "the two Sahihs" are the most universally authenticated |
| Hindi: dropped from schema entirely | Keep partial/inconsistent coverage; substitute Urdu | No authentic Hindi Hadith/Tafsir source found (checked `fawazahmed0/hadith-api`'s full edition list); user chose consistency over fake/partial coverage |
| Quran source: `api.alquran.cloud` over `fawazahmed0/quran-api` | `fawazahmed0/quran-api` (Unlicense, same author family as the hadith source) | `alquran.cloud` unambiguously names its editions "Saheeh International" / "Muhiuddin Khan"; `fawazahmed0/quran-api`'s matching entry is labeled "Umm Muhammad" — almost certainly the same translation (a known alternate credit for Saheeh International) but requires an inference rather than a direct match, so the unambiguous source was chosen |
| Tafsir schema: single `ayah_number`, not a range | `ayah_start`/`ayah_end` (originally proposed) | Corrected after actually fetching real Ibn Kathir data: the source already returns one row per ayah, duplicating text across grouped ayat itself — no range logic needed on our end |
| Embeddings: English-only | All 3-4 languages | RAG/citations are English-only today; keeps the vector index smaller |
| KB storage: separate `KnowledgeBaseDatabase`, always read-only | Merge into `AppDatabase` | Matches "always read-only" literally; clean separation from the read-write personalization data planned for later |
| Ship model: bundled by default + optional update | Fully download-required, like the LLM | KB is core functionality (Quran reading), not opt-in AI — tens of MB, small enough to bundle; blank first run would be bad UX |
| Build pipeline: reuse `RagRepository.populateVectorIndex()` | Write a new bespoke indexer | That method's logic was already correct — it was just fed fake data on-device; fixing `EmbeddingService` and running it once, offline, is the whole pipeline |
| Personalization RAG / AI-translation-on-demand | Design now vs. later | Deferred — distinct scope, each deserves its own design pass |
| `vec_knowledge_base` shape: plain BLOB fallback table | Real `vec0` virtual table | `sqlite-vec` was found not to actually load in this environment despite being marked "Completed" in `Tracker.md` — building against the format that's confirmed to work everywhere beats depending on one that isn't confirmed to work anywhere |

### Source verification trail (so this is auditable, not just asserted)

- `api.alquran.cloud/v1/edition` — fetched live, confirmed `quran-uthmani`, `en.sahih` ("Saheeh International"), `bn.bengali` ("Muhiuddin Khan") exist.
- `api.alquran.cloud/v1/quran/quran-uthmani` — fetched live, confirmed 114 surahs / 6,236 ayahs total (matches the standard Hafs/Uthmani count) and exact JSON shape.
- `github.com/fawazahmed0/hadith-api` — confirmed real (529 stars, Unlicense) via GitHub API; fetched `editions.json` live, confirmed Bukhari/Muslim have Arabic/English/Bengali editions and no Hindi edition exists in any collection.
- `github.com/spa5k/tafsir_api` — confirmed real (181 stars, MIT) via GitHub API; fetched its README for the exact endpoint pattern (initial guessed URL 404'd — corrected from the documented pattern, not guessed twice); fetched real Ibn Kathir English/Bengali tafsir for surah 1, confirmed content and the grouped-ayah duplication behavior.
- `huggingface.co/BAAI/bge-small-en-v1.5` and `Xenova/bge-small-en-v1.5` — confirmed MIT license via HF API; confirmed real `onnx/model_quantized.onnx` (34,014,426 bytes) and `vocab.txt` (231,508 bytes) via direct HEAD/GET requests.
- `pub.dev/packages/bert_tokenizer` — confirmed real, v1.1.1, published days before this design.
- `sqlite-vec` native loading — tested directly against `AppDatabase.forTesting`'s real `_createVirtualTable()` path (not assumed from `Tracker.md`'s "Completed" mark): `hasVectorExtension` is `false`, `CREATE VIRTUAL TABLE ... USING vec0(...)` throws `no such module: vec0`, even though `loadSqliteVectorExtension()` itself reports no error.
