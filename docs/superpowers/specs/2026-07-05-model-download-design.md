# Runtime Model Download & Recommendation — Design

## Problem

`LlmService.getSelectedModelPath()` returns hardcoded Flutter asset paths
(`assets/models/gemma_4_e2b.gguf`, `assets/models/gemma_4_e4b.gguf`), but no
such assets exist or are bundled (`assets/models/` only has `.gitkeep`) —
Gemma 4 GGUF weights are multi-gigabyte and can't reasonably ship in the app
bundle. As a result the app always runs `LlmService`'s mock-response
fallback; on-device inference has never actually run.

Separately, `LlmService._detectDeviceRamGb()` — meant to pick e2b vs. e4b
based on device RAM — only reads `/proc/meminfo` when `Platform.isLinux`.
On real Android devices that's always `false`, so it silently returns the
hardcoded 4.0GB fallback regardless of actual device RAM. The
"recommend a tier based on device spec" feature has never worked on Android.

## Solution

Users download a real GGUF model at runtime from Hugging Face, choosing
between two tiers (matching the app's existing E2B/"Lighter" and
E4B/"Standard" naming), with the RAM-appropriate tier flagged as
recommended. This is a deliberate, explicit exception to the project's
offline-first "No Unapproved Networks" rule — see the Rules.md amendment
below. Once downloaded, all inference stays on-device; no other network
calls are introduced.

### Rules.md amendment

Update the "Technical & Offline-First Constraints" section:

```markdown
*   **No Unapproved Networks:** Core packages must not make any external
    network requests. All dependencies (translations, databases) must
    reside locally in assets or application sandboxes. Exception: LLM
    model *files* may be fetched at runtime from Hugging Face,
    user-initiated, so users aren't forced to ship multi-GB weights in the
    app bundle. Once downloaded, all inference and RAG indexing still run
    fully on-device — no other network calls are introduced.
```

### Model catalog

New `lib/core/models/model_catalog.dart`. A small static list — no fetched
metadata, no search, no arbitrary user-supplied URLs. Two entries, verified
real and openly downloadable (unofficial `unsloth` GGUF mirrors — Google's
own official Gemma GGUF repos are gated behind Hugging Face auth + license
acceptance, which isn't feasible for an anonymous in-app download):

| id | Display name | HF repo | Filename | Size (bytes) | Recommended above |
|---|---|---|---|---|---|
| `e2b` | Gemma 4 E2B (Lighter) | `unsloth/gemma-4-E2B-it-GGUF` | `gemma-4-E2B-it-Q4_K_M.gguf` | 3106736256 | — (default) |
| `e4b` | Gemma 4 E4B (Standard) | `unsloth/gemma-4-E4B-it-GGUF` | `gemma-4-E4B-it-Q4_K_M.gguf` | 4977169568 | ≥ 6.0 GB RAM |

```dart
class ModelInfo {
  final String id;
  final String displayName;
  final String description;
  final String huggingFaceRepo;
  final String filename;
  final int sizeBytes;
  final double? recommendedAboveRamGb; // null = default/fallback tier

  const ModelInfo({
    required this.id,
    required this.displayName,
    required this.description,
    required this.huggingFaceRepo,
    required this.filename,
    required this.sizeBytes,
    this.recommendedAboveRamGb,
  });

  String get downloadUrl =>
      'https://huggingface.co/$huggingFaceRepo/resolve/main/$filename';
}

const List<ModelInfo> kModelCatalog = [
  ModelInfo(
    id: 'e2b',
    displayName: 'Gemma 4 E2B (Lighter)',
    description: 'Recommended for devices with <6GB RAM',
    huggingFaceRepo: 'unsloth/gemma-4-E2B-it-GGUF',
    filename: 'gemma-4-E2B-it-Q4_K_M.gguf',
    sizeBytes: 3106736256,
  ),
  ModelInfo(
    id: 'e4b',
    displayName: 'Gemma 4 E4B (Standard)',
    description: 'Recommended for devices with ≥6GB RAM',
    huggingFaceRepo: 'unsloth/gemma-4-E4B-it-GGUF',
    filename: 'gemma-4-E4B-it-Q4_K_M.gguf',
    sizeBytes: 4977169568,
    recommendedAboveRamGb: 6.0,
  ),
];
```

`ModelInfo.recommendedFor(double ramGb)` (a top-level function or static
helper) picks the highest-tier entry whose `recommendedAboveRamGb` the
device meets, falling back to the first (e2b) entry — this replaces the
threshold logic currently inlined in `LlmService.getSelectedModelPath()`.

### ModelDownloadService

New `lib/core/services/model_download_service.dart`. Uses `package:http`
(new dependency — the official Dart-team HTTP package; its `MockClient`
test double from `package:http/testing.dart` is what makes the
resumable-download logic testable without standing up a real server).

Storage: `<ApplicationDocumentsDirectory>/models/<filename>`, via
`path_provider` (already a dependency, same pattern `AppDatabase` uses for
its own file).

```dart
class DownloadProgress {
  final int bytesReceived;
  final int totalBytes;
  const DownloadProgress(this.bytesReceived, this.totalBytes);
  double get fraction => totalBytes == 0 ? 0 : bytesReceived / totalBytes;
}

class ModelDownloadService {
  final http.Client _client;
  ModelDownloadService({http.Client? client}) : _client = client ?? http.Client();

  Future<String> _modelsDir() async { ... } // ApplicationDocumentsDirectory/models, created if missing
  Future<String> localPathFor(ModelInfo model) async => '${await _modelsDir()}/${model.filename}';

  /// True only if the file exists AND its size matches [ModelInfo.sizeBytes]
  /// exactly — a partial/interrupted download must not read as "downloaded".
  Future<bool> isDownloaded(ModelInfo model) async { ... }

  /// Downloads (or resumes) [model], calling [onProgress] as bytes arrive.
  /// Resume: if a partial file already exists and is smaller than
  /// model.sizeBytes, sends `Range: bytes=<existing-length>-` and appends
  /// to the existing file instead of restarting. Throws on HTTP status
  /// codes other than 200 (fresh) or 206 (partial content, resumed).
  Future<void> downloadModel(
    ModelInfo model, {
    void Function(DownloadProgress)? onProgress,
  }) async { ... }

  Future<void> deleteModel(ModelInfo model) async { ... }
}
```

Error handling: `downloadModel` lets exceptions (network failure, non-2xx
status) propagate to the caller — the Settings UI catches them, leaves the
partial file in place (so a retry can resume), and shows an inline error
with a Retry action. No retry/backoff loop inside the service itself —
YAGNI for v1; the user re-tapping Download is the retry mechanism.

### LlmService changes

- `_detectDeviceRamGb()`: broaden the platform check from `Platform.isLinux`
  to `Platform.isLinux || Platform.isAndroid` — `/proc/meminfo` is
  world-readable on Android, no new permission needed.
- `getSelectedModelPath()`: replace the hardcoded asset-path branches with
  a lookup against `ModelDownloadService.localPathFor()` for the user's
  selected (or recommended-default) `ModelInfo`. If the resulting file
  doesn't exist (`isDownloaded` is false), return `null` instead of a path —
  `LlmService.init()`'s existing `try { LlamaFfi(...) } catch (_) {
  _useMock = true }` already treats any load failure as "use mock", so a
  `null`/missing path naturally falls through to the current mock behavior
  with no new branching needed there.

### Settings UI changes

Extends the existing "AI Model" `_buildSectionCard` section in
`settings_screen.dart` in place (still just 2 models — a dedicated screen
would be premature). Per-model row shows: name, size, a "Recommended for
your device" badge (computed once via `ModelInfo.recommendedFor(ramGb)` at
load time) on whichever tier matches, and one of:

- **Not downloaded:** a "Download" button. Tapping shows a confirmation
  dialog naming the exact size ("Download Gemma 4 E2B (2.9GB)?"). Confirming
  starts the download and switches the row to a progress bar.
- **Downloading:** a progress bar bound to `DownloadProgress.fraction`, plus
  a Cancel action (cancels the underlying `http` request; the partial file
  stays on disk for a future resume).
- **Downloaded:** the existing `RadioListTile` selection behavior
  (unchanged — still persists to `selected_llm_model` via
  `UserRepository.setEngagementValue`), plus a trash-icon "Delete" button
  with a confirmation dialog.

New "Wi-Fi only downloads" `SwitchListTile` in the same section, default
**on**, persisted as `wifi_only_model_downloads` via the existing
`UserRepository` key-value store. Backed by `connectivity_plus` (second new
dependency): before starting a download, if the toggle is on and
`Connectivity().checkConnectivity()` doesn't include `ConnectivityResult.wifi`,
show a message ("Turn off Wi-Fi-only downloads in Settings, or connect to
Wi-Fi, to download this model.") instead of starting.

### Manifest changes

Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```
Neither exists today — the app has been fully offline, so `INTERNET` was
never needed until now.

## Data flow

```
Settings screen load
  → ModelDownloadService.isDownloaded() per catalog entry
  → LlmService._detectDeviceRamGb() (now Android-aware)
  → ModelInfo.recommendedFor(ramGb) → badge on matching row

User taps Download on a row
  → confirm dialog (size) → [if Wi-Fi-only on] connectivity check
  → ModelDownloadService.downloadModel(model, onProgress: ...)
      → GET (or Range GET if resuming) huggingface.co/.../resolve/main/<file>
      → stream bytes to <AppDocs>/models/<file>, report progress
  → on success: row flips to Downloaded; on failure: inline error + Retry
      (retry re-invokes downloadModel, which resumes from the partial file)

Q&A / daily story generation
  → LlmService.getSelectedModelPath() → ModelDownloadService.localPathFor()
  → file exists? real llama.cpp path : existing mock fallback (unchanged)
```

## Testing

- `ModelDownloadService`: unit tests via `http`'s `MockClient` — fresh
  download writes the full byte stream to the expected path; a pre-existing
  partial file triggers a `Range` request and the response is appended
  (not overwritten); `isDownloaded` is false for a partial-size file and
  true only when the size matches exactly; `deleteModel` removes the file.
- `LlmService._detectDeviceRamGb()`: existing test already covers the
  `/proc/meminfo`-on-Linux path (this dev/test environment); the broadened
  `Platform.isAndroid` branch isn't independently testable here (no Android
  test runner in this environment) — noted as a gap, consistent with how
  Task 8.2's device-dependent work has already been described as blocked in
  Tracker.md.
- `ModelInfo.recommendedFor()`: a plain unit test, no I/O.
- Settings UI changes: `flutter analyze` only, consistent with the rest of
  the codebase's convention (no widget-test infrastructure exists anywhere
  in this project).

## Out of scope

- Embedding model (ONNX) downloads — LLM only, per earlier decision.
- A model "marketplace" / search / arbitrary user-supplied URLs — the
  catalog is a fixed, curated list of two entries.
- Waiting on an official, non-gated Google GGUF source — revisit if one
  becomes available; documented as a known provenance tradeoff (unofficial
  mirror vs. official gated repo) rather than solved.
- A third, larger tier (12B) for very high-RAM devices — explicitly
  deferred; the two-tier split matches the app's existing UI and RAM
  heuristic exactly.
