# Runtime Model Download & Recommendation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users download real Gemma 4 GGUF weights from Hugging Face at runtime (resumable), with the RAM-appropriate tier recommended, replacing `LlmService`'s currently-nonexistent bundled-asset model paths.

**Architecture:** A static two-entry model catalog; a `ModelDownloadService` built on `package:http` doing resumable (HTTP Range) downloads to app-local storage; a fix to `LlmService`'s RAM detection (currently non-functional on Android) and its model-path resolution; a Settings UI extension for download/progress/delete/Wi-Fi-only-toggle.

**Tech Stack:** Flutter, `package:http` (new dependency), `connectivity_plus` (new dependency), `path_provider` (already a dependency), Riverpod.

## Global Constraints

- No models are official/gated Google repos — use `unsloth/gemma-4-E2B-it-GGUF` and `unsloth/gemma-4-E4B-it-GGUF` (Q4_K_M), verified real and openly downloadable.
- `getSelectedModelPath()` returns `null` (not a fake path) when the selected model isn't downloaded — `LlmService.init()`'s existing `catch (_) { _useMock = true }` already treats any load failure as "use mock," so this requires no new branching there.
- `isDownloaded` is true only when the local file's size matches `ModelInfo.sizeBytes` exactly — a partial download must never read as complete.
- Downloads must resume via HTTP Range requests, not restart from scratch, when a partial file already exists.
- `flutter analyze` must stay at zero `error`-level issues; `flutter test` must stay fully green.
- No widget-test infrastructure exists in this codebase (still true) — UI-only tasks are verified via `flutter analyze`, not new widget tests.

---

### Task 1: Model catalog

**Files:**
- Create: `lib/core/models/model_catalog.dart`
- Test: `test/core/models/model_catalog_test.dart`

**Interfaces:**
- Produces (used by Tasks 3, 4, 5):
  - `class ModelInfo` with fields `id`, `displayName`, `description`, `huggingFaceRepo`, `filename`, `sizeBytes` (`int`), `recommendedAboveRamGb` (`double?`), and getter `downloadUrl` (`String`).
  - `const List<ModelInfo> kModelCatalog` — exactly two entries, ids `'e2b'` and `'e4b'`.
  - `ModelInfo recommendedModelFor(double ramGb)` — top-level function.
  - `ModelInfo modelById(String id)` — top-level function.

- [ ] **Step 1: Write the failing test**

Create `test/core/models/model_catalog_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/models/model_catalog.dart';

void main() {
  group('Model catalog', () {
    test('has exactly two entries: e2b and e4b', () {
      expect(kModelCatalog.length, 2);
      expect(kModelCatalog.map((m) => m.id), containsAll(['e2b', 'e4b']));
    });

    test('downloadUrl builds the correct Hugging Face resolve URL', () {
      final e2b = modelById('e2b');
      expect(
        e2b.downloadUrl,
        'https://huggingface.co/${e2b.huggingFaceRepo}/resolve/main/${e2b.filename}',
      );
    });

    test('modelById returns the matching entry', () {
      expect(modelById('e4b').id, 'e4b');
    });

    test('modelById falls back to the first entry for an unknown id', () {
      expect(modelById('nonexistent').id, kModelCatalog.first.id);
    });

    test('recommendedModelFor picks e2b below the e4b RAM threshold', () {
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

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/models/model_catalog_test.dart`
Expected: FAIL to compile — `Error when reading 'lib/core/models/model_catalog.dart': No such file or directory` (or `Target of URI doesn't exist`).

- [ ] **Step 3: Implement the catalog**

Create `lib/core/models/model_catalog.dart`:

```dart
/// A downloadable GGUF model tier.
class ModelInfo {
  final String id;
  final String displayName;
  final String description;
  final String huggingFaceRepo;
  final String filename;
  final int sizeBytes;

  /// If non-null, this model becomes the recommendation once the device's
  /// detected RAM meets or exceeds this many GB. The catalog entry with a
  /// null threshold is the default/fallback recommendation.
  final double? recommendedAboveRamGb;

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

/// Picks the highest-tier catalog entry whose [ModelInfo.recommendedAboveRamGb]
/// the device's RAM meets, falling back to the first (lowest-tier) entry.
ModelInfo recommendedModelFor(double ramGb) {
  var best = kModelCatalog.first;
  for (final model in kModelCatalog) {
    final threshold = model.recommendedAboveRamGb;
    if (threshold != null && ramGb >= threshold) {
      best = model;
    }
  }
  return best;
}

/// Looks up a catalog entry by id, falling back to the first entry if [id]
/// doesn't match anything (e.g. a stale/corrupted persisted setting).
ModelInfo modelById(String id) => kModelCatalog.firstWhere(
      (m) => m.id == id,
      orElse: () => kModelCatalog.first,
    );
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/models/model_catalog_test.dart`
Expected: PASS — all 6 tests green.

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze lib/core/models/model_catalog.dart test/core/models/model_catalog_test.dart`
Expected: `No issues found!`

```bash
git add lib/core/models/model_catalog.dart test/core/models/model_catalog_test.dart
git commit -m "feat: add model catalog for runtime Gemma 4 downloads"
```

---

### Task 2: Dependencies, permissions, and Rules.md amendment

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `Rules.md`

**Interfaces:**
- Produces (used by Task 3): `package:http` available for import.
- Produces (used by Task 5): `package:connectivity_plus` available for import.
- Produces: `INTERNET` and `ACCESS_NETWORK_STATE` manifest permissions (the app has never had either — it's been fully offline until now).

- [ ] **Step 1: Add dependencies to pubspec.yaml**

In `pubspec.yaml`, change:

```yaml
  # UI / Audio / Notifications
  google_fonts: ^8.1.0
  audioplayers: ^6.0.0
  flutter_local_notifications: ^22.0.0
  android_alarm_manager_plus: ^5.1.0
```

to:

```yaml
  # UI / Audio / Notifications
  google_fonts: ^8.1.0
  audioplayers: ^6.0.0
  flutter_local_notifications: ^22.0.0
  android_alarm_manager_plus: ^5.1.0

  # Runtime model downloads
  http: ^1.6.0
  connectivity_plus: ^7.2.0
```

- [ ] **Step 2: Fetch dependencies**

Run: `flutter pub get`
Expected: `Got dependencies!` with `http` and `connectivity_plus` listed as newly added in the output (or already present in `pubspec.lock` from a prior transitive resolution — either way, the command succeeds).

- [ ] **Step 3: Add Android manifest permissions**

In `android/app/src/main/AndroidManifest.xml`, change:

```xml
    <!-- Required to post prayer-time notifications on Android 13+ (API 33+). -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <application
```

to:

```xml
    <!-- Required to post prayer-time notifications on Android 13+ (API 33+). -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <!-- Needed to download LLM model weights from Hugging Face at runtime
         (ModelDownloadService) and to check connectivity type for the
         Wi-Fi-only-downloads setting. The app has no other network use. -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <application
```

- [ ] **Step 4: Amend Rules.md**

In `Rules.md`, change:

```markdown
*   **No Unapproved Networks:** Core packages must not make any external network requests. All dependencies (models, translations, databases) must reside locally in assets or application sandboxes.
```

to:

```markdown
*   **No Unapproved Networks:** Core packages must not make any external network requests. All dependencies (translations, databases) must reside locally in assets or application sandboxes. Exception: LLM model *files* may be fetched at runtime from Hugging Face, user-initiated, so users aren't forced to ship multi-GB weights in the app bundle. Once downloaded, all inference and RAG indexing still run fully on-device — no other network calls are introduced.
```

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze`
Expected: zero `error`-level issues (unchanged from before this task — this task touches no Dart source).

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml Rules.md
git commit -m "feat: add http/connectivity_plus deps, network permissions, Rules.md exception"
```

---

### Task 3: ModelDownloadService

**Files:**
- Create: `lib/core/services/model_download_service.dart`
- Test: `test/core/services/model_download_service_test.dart`

**Interfaces:**
- Consumes: `ModelInfo` (Task 1, `lib/core/models/model_catalog.dart`); `package:http` (Task 2).
- Produces (used by Tasks 4, 5):
  - `class DownloadProgress { final int bytesReceived; final int totalBytes; double get fraction; }`
  - `class ModelDownloadCancelledException implements Exception {}`
  - `class ModelDownloadService`:
    - `ModelDownloadService({http.Client? client})` — production constructor.
    - `ModelDownloadService.forTesting({required Directory modelsDir, http.Client? client})` — bypasses `path_provider` for tests.
    - `Future<String> localPathFor(ModelInfo model)`
    - `Future<bool> isDownloaded(ModelInfo model)`
    - `Future<void> downloadModel(ModelInfo model, {void Function(DownloadProgress)? onProgress})`
    - `void cancelDownload()`
    - `Future<void> deleteModel(ModelInfo model)`
  - `final modelDownloadServiceProvider = Provider<ModelDownloadService>(...)`

- [ ] **Step 1: Write the failing tests**

Create `test/core/services/model_download_service_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:learn_quran/core/models/model_catalog.dart';
import 'package:learn_quran/core/services/model_download_service.dart';

const _testModel = ModelInfo(
  id: 'test',
  displayName: 'Test Model',
  description: 'A tiny fixture, not a real model',
  huggingFaceRepo: 'test/repo',
  filename: 'test-model.gguf',
  sizeBytes: 20,
);

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('model_download_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ModelDownloadService', () {
    test('isDownloaded is false when no file exists', () async {
      final service = ModelDownloadService.forTesting(modelsDir: tempDir);
      expect(await service.isDownloaded(_testModel), isFalse);
    });

    test('isDownloaded is false for a partial-size file, true once complete', () async {
      final service = ModelDownloadService.forTesting(modelsDir: tempDir);
      final path = await service.localPathFor(_testModel);
      await File(path).writeAsBytes(List.filled(10, 65)); // 10 of 20 bytes
      expect(await service.isDownloaded(_testModel), isFalse);

      await File(path).writeAsBytes(List.filled(20, 65)); // now 20 of 20
      expect(await service.isDownloaded(_testModel), isTrue);
    });

    test('downloadModel writes the full response body to the expected path', () async {
      final expectedBytes = List<int>.generate(20, (i) => 65 + i); // 'A'..'T'
      final client = MockClient((request) async {
        expect(request.url.toString(), _testModel.downloadUrl);
        expect(request.headers.containsKey('Range'), isFalse);
        return http.Response.bytes(expectedBytes, 200);
      });
      final service = ModelDownloadService.forTesting(modelsDir: tempDir, client: client);

      final progressUpdates = <DownloadProgress>[];
      await service.downloadModel(_testModel, onProgress: progressUpdates.add);

      final path = await service.localPathFor(_testModel);
      expect(await File(path).readAsBytes(), expectedBytes);
      expect(await service.isDownloaded(_testModel), isTrue);
      expect(progressUpdates.last.bytesReceived, 20);
      expect(progressUpdates.last.totalBytes, 20);
    });

    test('downloadModel resumes a partial file via a Range request', () async {
      final path = '${tempDir.path}/${_testModel.filename}';
      final firstHalf = List<int>.generate(10, (i) => 65 + i); // 'A'..'J'
      final secondHalf = List<int>.generate(10, (i) => 75 + i); // 'K'..'T'
      await File(path).writeAsBytes(firstHalf);

      final client = MockClient((request) async {
        expect(request.headers['Range'], 'bytes=10-');
        return http.Response.bytes(secondHalf, 206);
      });
      final service = ModelDownloadService.forTesting(modelsDir: tempDir, client: client);

      await service.downloadModel(_testModel);

      expect(await File(path).readAsBytes(), [...firstHalf, ...secondHalf]);
      expect(await service.isDownloaded(_testModel), isTrue);
    });

    test('downloadModel restarts instead of appending when the server ignores Range', () async {
      final path = '${tempDir.path}/${_testModel.filename}';
      await File(path).writeAsBytes(List.filled(10, 65));
      final fullBody = List<int>.generate(20, (i) => 65 + i);

      // Server responds 200 (whole file) even though we sent a Range header —
      // must not append fullBody onto the stale partial bytes.
      final client = MockClient((request) async => http.Response.bytes(fullBody, 200));
      final service = ModelDownloadService.forTesting(modelsDir: tempDir, client: client);

      await service.downloadModel(_testModel);

      expect(await File(path).readAsBytes(), fullBody);
    });

    test('downloadModel throws on a non-2xx response', () async {
      final client = MockClient((request) async => http.Response('not found', 404));
      final service = ModelDownloadService.forTesting(modelsDir: tempDir, client: client);

      expect(() => service.downloadModel(_testModel), throwsException);
    });

    test('deleteModel removes the downloaded file', () async {
      final client = MockClient(
        (request) async => http.Response.bytes(List.filled(20, 65), 200),
      );
      final service = ModelDownloadService.forTesting(modelsDir: tempDir, client: client);
      await service.downloadModel(_testModel);
      expect(await service.isDownloaded(_testModel), isTrue);

      await service.deleteModel(_testModel);

      expect(await service.isDownloaded(_testModel), isFalse);
    });

    test('deleteModel on a non-existent file does not throw', () async {
      final service = ModelDownloadService.forTesting(modelsDir: tempDir);
      await service.deleteModel(_testModel); // should complete without error
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/services/model_download_service_test.dart`
Expected: FAIL to compile — `Target of URI doesn't exist: 'package:learn_quran/core/services/model_download_service.dart'`.

- [ ] **Step 3: Implement ModelDownloadService**

Create `lib/core/services/model_download_service.dart`:

```dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/model_catalog.dart';

/// Reports download progress. [fraction] is 0.0-1.0, or 0 if [totalBytes]
/// is unknown/zero.
class DownloadProgress {
  final int bytesReceived;
  final int totalBytes;
  const DownloadProgress(this.bytesReceived, this.totalBytes);
  double get fraction => totalBytes == 0 ? 0 : bytesReceived / totalBytes;
}

/// Thrown from [ModelDownloadService.downloadModel] when
/// [ModelDownloadService.cancelDownload] was called mid-download.
class ModelDownloadCancelledException implements Exception {
  @override
  String toString() => 'ModelDownloadCancelledException';
}

/// Downloads GGUF model files from Hugging Face to app-local storage,
/// resuming partial downloads via HTTP Range requests.
class ModelDownloadService {
  final http.Client _client;
  final Directory? _modelsDirOverride;
  bool _cancelRequested = false;

  ModelDownloadService({http.Client? client})
      : _client = client ?? http.Client(),
        _modelsDirOverride = null;

  /// For testing: bypasses path_provider and stores/reads files directly
  /// under [modelsDir] instead of `<ApplicationDocumentsDirectory>/models`.
  ModelDownloadService.forTesting({
    required Directory modelsDir,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _modelsDirOverride = modelsDir;

  Future<Directory> _modelsDir() async {
    final override = _modelsDirOverride;
    if (override != null) return override;
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> localPathFor(ModelInfo model) async {
    final dir = await _modelsDir();
    return '${dir.path}/${model.filename}';
  }

  /// True only if the local file exists AND its size matches
  /// [ModelInfo.sizeBytes] exactly — a partial/interrupted download must
  /// never read as "downloaded".
  Future<bool> isDownloaded(ModelInfo model) async {
    final file = File(await localPathFor(model));
    if (!await file.exists()) return false;
    return await file.length() == model.sizeBytes;
  }

  /// Downloads (or resumes) [model], calling [onProgress] as bytes arrive.
  /// If a partial file already exists and is smaller than
  /// [ModelInfo.sizeBytes], sends `Range: bytes=<existing-length>-` and
  /// appends the response to the existing file. If the server responds
  /// 200 (ignoring the Range request) rather than 206, the download
  /// restarts from scratch instead of appending onto stale bytes.
  Future<void> downloadModel(
    ModelInfo model, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    _cancelRequested = false;
    final path = await localPathFor(model);
    final file = File(path);
    final existingLength = await file.exists() ? await file.length() : 0;

    // Exact match only — this must agree with isDownloaded's exact-size
    // check. An oversized/corrupt file (> sizeBytes) falls through and
    // restarts the download below rather than silently no-op'ing forever.
    if (existingLength == model.sizeBytes) {
      onProgress?.call(DownloadProgress(existingLength, model.sizeBytes));
      return;
    }

    final validPartial = existingLength > 0 && existingLength < model.sizeBytes;
    final request = http.Request('GET', Uri.parse(model.downloadUrl));
    if (validPartial) {
      request.headers['Range'] = 'bytes=$existingLength-';
    }

    final response = await _client.send(request);
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw HttpException(
        'Unexpected status ${response.statusCode} downloading ${model.displayName}',
      );
    }

    final resuming = response.statusCode == 206 && validPartial;
    final sink = file.openWrite(
      mode: resuming ? FileMode.append : FileMode.write,
    );
    var received = resuming ? existingLength : 0;

    try {
      await for (final chunk in response.stream) {
        if (_cancelRequested) {
          throw ModelDownloadCancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(DownloadProgress(received, model.sizeBytes));
      }
    } finally {
      await sink.close();
    }
  }

  /// Signals the in-flight [downloadModel] call (if any) to stop after its
  /// next chunk. The partial file is left on disk so a later call can
  /// resume from it.
  void cancelDownload() {
    _cancelRequested = true;
  }

  Future<void> deleteModel(ModelInfo model) async {
    final file = File(await localPathFor(model));
    if (await file.exists()) {
      await file.delete();
    }
  }
}

final modelDownloadServiceProvider = Provider<ModelDownloadService>((ref) {
  return ModelDownloadService();
});
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/core/services/model_download_service_test.dart`
Expected: PASS — all 8 tests green.

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze lib/core/services/model_download_service.dart test/core/services/model_download_service_test.dart`
Expected: `No issues found!`

```bash
git add lib/core/services/model_download_service.dart test/core/services/model_download_service_test.dart
git commit -m "feat: add ModelDownloadService with resumable HTTP Range downloads"
```

---

### Task 4: LlmService — real Android RAM detection and model-path resolution

**Files:**
- Modify: `lib/core/services/llm_service.dart`
- Modify: `test/core/services/llm_service_test.dart`

**Interfaces:**
- Consumes: `ModelInfo`, `kModelCatalog`, `recommendedModelFor`, `modelById` (Task 1); `ModelDownloadService` (Task 3).
- Produces: `LlmService.getSelectedModelPath()` now returns `Future<String?>` (was `Future<String>`) — `null` means "not downloaded, caller should treat as no local model available." `LlmService.detectDeviceRamGb()` is now public (was private `_detectDeviceRamGb()`) so Task 5's Settings UI can reuse it. Constructor becomes `LlmService([UserRepository? userRepo, ModelDownloadService? downloadService])` — both existing call sites (`LlmService(userRepo)` in the provider, `LlmService()` in other tests) remain valid since both new params are optional.

- [ ] **Step 1: Write the failing tests**

In `test/core/services/llm_service_test.dart`, replace the two `getSelectedModelPath` tests:

```dart
    test('getSelectedModelPath returns model based on RAM default', () async {
      final path = await service.getSelectedModelPath();
      final meminfo = File('/proc/meminfo');
      double ramGb = 4.0;
      if (meminfo.existsSync()) {
        final lines = meminfo.readAsLinesSync();
        for (final line in lines) {
          if (line.startsWith('MemTotal:')) {
            final match = RegExp(r'\d+').firstMatch(line);
            if (match != null) {
              final totalKb = int.parse(match.group(0)!);
              ramGb = totalKb / (1024 * 1024);
            }
          }
        }
      }
      if (ramGb >= 6.0) {
        expect(path, 'assets/models/gemma_4_e4b.gguf');
      } else {
        expect(path, 'assets/models/gemma_4_e2b.gguf');
      }
    });

    test('getSelectedModelPath respects user settings selection', () async {
      await userRepo.setEngagementValue('selected_llm_model', 'e4b');
      final path = await service.getSelectedModelPath();
      expect(path, 'assets/models/gemma_4_e4b.gguf');

      await userRepo.setEngagementValue('selected_llm_model', 'e2b');
      final path2 = await service.getSelectedModelPath();
      expect(path2, 'assets/models/gemma_4_e2b.gguf');
    });
```

with:

```dart
    test('getSelectedModelPath returns null when nothing is downloaded', () async {
      final path = await service.getSelectedModelPath();
      expect(path, isNull);
    });

    test('getSelectedModelPath returns the local file once the recommended model is downloaded', () async {
      final recommended = recommendedModelFor(service.detectDeviceRamGb());
      await _createFakeDownloadedFile(tempModelsDir, recommended);

      final path = await service.getSelectedModelPath();
      expect(path, '${tempModelsDir.path}/${recommended.filename}');
    });

    test("getSelectedModelPath respects the user's selected_llm_model over the RAM default", () async {
      await userRepo.setEngagementValue('selected_llm_model', 'e4b');
      final e4b = modelById('e4b');
      await _createFakeDownloadedFile(tempModelsDir, e4b);

      final path = await service.getSelectedModelPath();
      expect(path, '${tempModelsDir.path}/${e4b.filename}');
    });

    test('getSelectedModelPath returns null if the selected model is only partially downloaded', () async {
      await userRepo.setEngagementValue('selected_llm_model', 'e2b');
      final e2b = modelById('e2b');
      final path = '${tempModelsDir.path}/${e2b.filename}';
      final raf = await File(path).open(mode: FileMode.write);
      await raf.truncate(e2b.sizeBytes - 1024); // one KB short of complete
      await raf.close();

      final result = await service.getSelectedModelPath();
      expect(result, isNull);
    });
```

Add the helper (used above) and the new imports/setup at the top of the file. Replace:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:learn_quran/data/local/db/app_database.dart';
import 'package:learn_quran/data/repositories/user_repository.dart';
import 'package:learn_quran/core/services/llm_service.dart';

void main() {
  late AppDatabase db;
  late UserRepository userRepo;
  late LlmService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    userRepo = UserRepository(db);
    service = LlmService(userRepo);
  });

  tearDown(() async {
    await db.close();
  });
```

with:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:learn_quran/data/local/db/app_database.dart';
import 'package:learn_quran/data/repositories/user_repository.dart';
import 'package:learn_quran/core/services/llm_service.dart';
import 'package:learn_quran/core/services/model_download_service.dart';
import 'package:learn_quran/core/models/model_catalog.dart';

/// Creates a sparse file of exactly [model.sizeBytes] length, without
/// writing real content — real Gemma 4 sizes are multi-gigabyte, so
/// actually allocating that much memory/disk per test would be absurd.
/// `File.truncate` creates a sparse file on this dev machine's filesystem.
Future<void> _createFakeDownloadedFile(Directory dir, ModelInfo model) async {
  final raf = await File('${dir.path}/${model.filename}').open(mode: FileMode.write);
  await raf.truncate(model.sizeBytes);
  await raf.close();
}

void main() {
  late AppDatabase db;
  late UserRepository userRepo;
  late Directory tempModelsDir;
  late ModelDownloadService downloadService;
  late LlmService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    userRepo = UserRepository(db);
    tempModelsDir = Directory.systemTemp.createTempSync('llm_service_test_');
    downloadService = ModelDownloadService.forTesting(modelsDir: tempModelsDir);
    service = LlmService(userRepo, downloadService);
  });

  tearDown(() async {
    await db.close();
    if (await tempModelsDir.exists()) {
      await tempModelsDir.delete(recursive: true);
    }
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/services/llm_service_test.dart`
Expected: FAIL — compile error (`LlmService(userRepo, downloadService)` — too many positional arguments; `detectDeviceRamGb` undefined) or, once that's patched locally in your head, behavioral failures (`getSelectedModelPath` still returns a hardcoded asset string, not `null`).

- [ ] **Step 3: Implement the LlmService changes**

In `lib/core/services/llm_service.dart`, replace:

```dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/user_repository.dart';
import '../providers/repository_providers.dart';
import 'llama_ffi.dart';

class LlmService {
  final UserRepository? _userRepo;
  bool _initialized = false;
  bool _useMock = true;
  LlamaFfi? _ffi;

  LlmService([this._userRepo]);

  Future<String> getSelectedModelPath() async {
    if (_userRepo != null) {
      final selectedModel = await _userRepo.getEngagementValue('selected_llm_model');
      if (selectedModel == 'e2b') {
        return 'assets/models/gemma_4_e2b.gguf';
      } else if (selectedModel == 'e4b') {
        return 'assets/models/gemma_4_e4b.gguf';
      }
    }

    final ramGb = _detectDeviceRamGb();
    if (ramGb >= 6.0) {
      return 'assets/models/gemma_4_e4b.gguf';
    } else {
      return 'assets/models/gemma_4_e2b.gguf';
    }
  }

  double _detectDeviceRamGb() {
    try {
      if (Platform.isLinux) {
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
```

with:

```dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/user_repository.dart';
import '../providers/repository_providers.dart';
import '../models/model_catalog.dart';
import 'llama_ffi.dart';
import 'model_download_service.dart';

class LlmService {
  final UserRepository? _userRepo;
  final ModelDownloadService _downloadService;
  bool _initialized = false;
  bool _useMock = true;
  LlamaFfi? _ffi;

  LlmService([this._userRepo, ModelDownloadService? downloadService])
      : _downloadService = downloadService ?? ModelDownloadService();

  /// Resolves the user's selected model (or the RAM-based recommendation if
  /// nothing's been explicitly selected), then returns its local file path
  /// if it's actually downloaded — or null if it isn't, so callers can fall
  /// back to mock/no-model behavior rather than trying to load a
  /// nonexistent file.
  Future<String?> getSelectedModelPath() async {
    final model = await _resolveSelectedModel();
    if (await _downloadService.isDownloaded(model)) {
      return _downloadService.localPathFor(model);
    }
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
```

Leave the rest of the file (`init()`, `generateResponseStream()`, `_generateMockResponse()`, the `llmServiceProvider` at the bottom) unchanged — this task only touches model-path resolution and RAM detection, not the (still-mocked) inference path itself.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/core/services/llm_service_test.dart`
Expected: PASS — all 6 tests green (2 unchanged `generateResponseStream` tests + 4 new/changed `getSelectedModelPath` tests).

- [ ] **Step 5: Run the full suite, analyze, and commit**

Run: `flutter test`
Expected: all tests pass (no other file calls `getSelectedModelPath` or `_detectDeviceRamGb`, so nothing else should be affected).

Run: `flutter analyze lib/core/services/llm_service.dart test/core/services/llm_service_test.dart`
Expected: `No issues found!`

```bash
git add lib/core/services/llm_service.dart test/core/services/llm_service_test.dart
git commit -m "fix: real Android RAM detection; getSelectedModelPath returns real download path or null"
```

---

### Task 5: Settings UI — download, progress, delete, Wi-Fi-only toggle

**Files:**
- Modify: `lib/presentation/screens/settings_screen.dart`

**Interfaces:**
- Consumes: `kModelCatalog`, `ModelInfo`, `recommendedModelFor` (Task 1); `modelDownloadServiceProvider`, `DownloadProgress` (Task 3); `llmServiceProvider`, `LlmService.detectDeviceRamGb()` (Task 4, already public); `package:connectivity_plus` (Task 2).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add imports and state fields**

In `lib/presentation/screens/settings_screen.dart`, replace:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/services/notification_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  String _selectedLanguage = 'English';
  String _selectedModel = 'e2b';
  String _calculationMethod = 'muslim_world_league';
  bool _salatNotifications = true;
  bool _notificationsEnabled = false;
  bool _exactAlarmsEnabled = false;
  bool _checkingPermissions = true;
```

with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/llm_service.dart';
import '../../core/services/model_download_service.dart';
import '../../core/models/model_catalog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  String _selectedLanguage = 'English';
  String _selectedModel = 'e2b';
  String _calculationMethod = 'muslim_world_league';
  bool _salatNotifications = true;
  bool _notificationsEnabled = false;
  bool _exactAlarmsEnabled = false;
  bool _checkingPermissions = true;
  Map<String, bool> _modelDownloaded = {};
  String? _recommendedModelId;
  String? _downloadingModelId;
  double _downloadProgress = 0.0;
  bool _wifiOnlyDownloads = true;
```

- [ ] **Step 2: Load model statuses on init and add the download/delete/format methods**

Replace:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => _loadSettings());
    _checkPermissions();
  }
```

with:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => _loadSettings());
    _checkPermissions();
    _checkModelStatuses();
  }
```

Then, right after the existing `_grantExactAlarms` method (before `_loadSettings`), insert:

```dart
  Future<void> _checkModelStatuses() async {
    final downloadService = ref.read(modelDownloadServiceProvider);
    final statuses = <String, bool>{};
    for (final model in kModelCatalog) {
      statuses[model.id] = await downloadService.isDownloaded(model);
    }
    final ramGb = ref.read(llmServiceProvider).detectDeviceRamGb();
    if (mounted) {
      setState(() {
        _modelDownloaded = statuses;
        _recommendedModelId = recommendedModelFor(ramGb).id;
      });
    }
  }

  String _formatSize(int bytes) {
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(1)}GB';
  }

  Future<void> _downloadModel(ModelInfo model) async {
    if (_wifiOnlyDownloads) {
      final results = await Connectivity().checkConnectivity();
      if (!results.contains(ConnectivityResult.wifi)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Turn off Wi-Fi-only downloads in Settings, or connect to Wi-Fi, to download this model.'),
            ),
          );
        }
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Download ${model.displayName}?'),
        content: Text(
            'This will download ${_formatSize(model.sizeBytes)} from Hugging Face.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _downloadingModelId = model.id;
      _downloadProgress = 0.0;
    });

    try {
      await ref.read(modelDownloadServiceProvider).downloadModel(
        model,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _downloadProgress = progress.fraction);
          }
        },
      );
      if (mounted) {
        setState(() {
          _modelDownloaded[model.id] = true;
          _downloadingModelId = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _downloadingModelId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Failed to download ${model.displayName}. Tap Download to retry.')),
        );
      }
    }
  }

  Future<void> _deleteModel(ModelInfo model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${model.displayName}?'),
        content: const Text('You can download it again later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(modelDownloadServiceProvider).deleteModel(model);
    if (mounted) {
      setState(() => _modelDownloaded[model.id] = false);
    }
  }

  Widget _buildModelRow(ThemeData theme, ModelInfo model) {
    final isDownloaded = _modelDownloaded[model.id] ?? false;
    final isDownloading = _downloadingModelId == model.id;
    final isRecommended = _recommendedModelId == model.id;

    final titleText = Text(
      isRecommended ? '${model.displayName} • Recommended' : model.displayName,
      style: theme.textTheme.bodyMedium,
    );
    final subtitleText = Text(
      '${_formatSize(model.sizeBytes)} — ${model.description}',
      style: theme.textTheme.labelLarge,
    );

    if (isDownloading) {
      return ListTile(
        title: titleText,
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(
            value: _downloadProgress,
            color: AppTheme.emeraldGreen,
          ),
        ),
      );
    }

    if (isDownloaded) {
      return RadioListTile<String>(
        title: titleText,
        subtitle: subtitleText,
        value: model.id,
        activeColor: AppTheme.emeraldGreen,
        secondary: IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
          onPressed: () => _deleteModel(model),
        ),
      );
    }

    return ListTile(
      title: titleText,
      subtitle: subtitleText,
      trailing: TextButton(
        onPressed: () => _downloadModel(model),
        child: const Text('Download'),
      ),
    );
  }
```

- [ ] **Step 3: Load the Wi-Fi-only setting**

In `_loadSettings`, replace:

```dart
  Future<void> _loadSettings() async {
    final userRepo = ref.read(userRepositoryProvider);
    final lang = await userRepo.getEngagementValue('selected_language') ?? 'English';
    final model = await userRepo.getEngagementValue('selected_llm_model') ?? 'e2b';
    final method = await userRepo.getEngagementValue('calculation_method') ?? 'muslim_world_league';
    final notifs = await userRepo.getEngagementValue('salat_notifications') ?? 'true';

    if (mounted) {
      setState(() {
        _selectedLanguage = lang;
        _selectedModel = model;
        _calculationMethod = method;
        _salatNotifications = notifs == 'true';
      });
    }
  }
```

with:

```dart
  Future<void> _loadSettings() async {
    final userRepo = ref.read(userRepositoryProvider);
    final lang = await userRepo.getEngagementValue('selected_language') ?? 'English';
    final model = await userRepo.getEngagementValue('selected_llm_model') ?? 'e2b';
    final method = await userRepo.getEngagementValue('calculation_method') ?? 'muslim_world_league';
    final notifs = await userRepo.getEngagementValue('salat_notifications') ?? 'true';
    final wifiOnly = await userRepo.getEngagementValue('wifi_only_model_downloads') ?? 'true';

    if (mounted) {
      setState(() {
        _selectedLanguage = lang;
        _selectedModel = model;
        _calculationMethod = method;
        _salatNotifications = notifs == 'true';
        _wifiOnlyDownloads = wifiOnly == 'true';
      });
    }
  }
```

- [ ] **Step 4: Replace the static AI Model section with the dynamic rows + Wi-Fi toggle**

Replace:

```dart
            // AI Model Selection
            _buildSectionCard(
              theme: theme,
              title: 'AI Model',
              icon: Icons.memory_rounded,
              children: [
                RadioGroup<String>(
                  groupValue: _selectedModel,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedModel = val);
                      _updateSetting('selected_llm_model', val);
                    }
                  },
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        title: Text('Gemma 4 e2b (Lighter)',
                            style: theme.textTheme.bodyMedium),
                        subtitle: Text('Recommended for devices with <6GB RAM',
                            style: theme.textTheme.labelLarge),
                        value: 'e2b',
                        activeColor: AppTheme.emeraldGreen,
                      ),
                      RadioListTile<String>(
                        title: Text('Gemma 4 e4b (Standard)',
                            style: theme.textTheme.bodyMedium),
                        subtitle: Text('Recommended for devices with ≥6GB RAM',
                            style: theme.textTheme.labelLarge),
                        value: 'e4b',
                        activeColor: AppTheme.emeraldGreen,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
```

with:

```dart
            // AI Model Selection
            _buildSectionCard(
              theme: theme,
              title: 'AI Model',
              icon: Icons.memory_rounded,
              children: [
                RadioGroup<String>(
                  groupValue: _selectedModel,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedModel = val);
                      _updateSetting('selected_llm_model', val);
                    }
                  },
                  child: Column(
                    children: kModelCatalog
                        .map((model) => _buildModelRow(theme, model))
                        .toList(),
                  ),
                ),
                SwitchListTile(
                  title: Text('Wi-Fi only downloads', style: theme.textTheme.bodyMedium),
                  subtitle: Text('Avoid using cellular data for multi-GB model downloads',
                      style: theme.textTheme.labelLarge),
                  value: _wifiOnlyDownloads,
                  activeThumbColor: AppTheme.emeraldGreen,
                  onChanged: (val) {
                    setState(() => _wifiOnlyDownloads = val);
                    _updateSetting('wifi_only_model_downloads', val.toString());
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
```

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze lib/presentation/screens/settings_screen.dart`
Expected: `No issues found!`

Run: `flutter test`
Expected: all tests pass (this task touches no test files; nothing here should regress the suite).

```bash
git add lib/presentation/screens/settings_screen.dart
git commit -m "feat: add model download/progress/delete UI and Wi-Fi-only toggle to Settings"
```

---

### Task 6: Final verification and release build

**Files:**
- Modify: `Tracker.md`

**Interfaces:**
- Consumes: nothing new — this task verifies Tasks 1-5 together.

- [ ] **Step 1: Full analyze**

Run: `flutter analyze`
Expected: zero `error`-level issues. Verify with:

Run: `flutter analyze 2>&1 | grep ' error •'`
Expected: no output.

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all tests pass, including the new model_catalog, model_download_service, and updated llm_service tests.

- [ ] **Step 3: Release build**

Run: `ANDROID_HOME="$HOME/Android/Sdk" flutter build apk --release`
Expected: `✓ Built build/app/outputs/flutter-apk/app-release.apk (...)`. `connectivity_plus` has native Android code (unlike the pure-Dart `http` package) — this is the step that would surface any Gradle/compileSdk conflict, similar to the `onnxruntime` issue hit earlier this project. If it fails with an AAR-metadata/compileSdk error, apply the same fix already in `android/build.gradle.kts` (the `subprojects { ... compileSdk = 36 }` block) — it already applies to every Android library module, so a new plugin needing it should already be covered without further changes.

- [ ] **Step 4: Update Tracker.md**

Add a new phase after Phase 9, mirroring the existing style:

```markdown

### Phase 10: Runtime Model Download
*   [x] **Task 10.1:** Build runtime Gemma 4 model download (Hugging Face, resumable), device-RAM-based recommendation, and Settings UI (download/progress/delete/Wi-Fi-only toggle). (Completed: 2026-07-05)
    See design: [docs/superpowers/specs/2026-07-05-model-download-design.md](docs/superpowers/specs/2026-07-05-model-download-design.md)
    Fixed a real bug found along the way: `LlmService._detectDeviceRamGb()`
    only checked `Platform.isLinux`, so it always fell back to a hardcoded
    4.0GB on real Android devices — the RAM-based recommendation never
    worked before this. Now checks `Platform.isAndroid` too.
```

- [ ] **Step 5: Commit**

```bash
git add Tracker.md
git commit -m "docs: mark runtime model download feature complete in Tracker"
```
