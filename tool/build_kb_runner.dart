import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'build_kb.dart' as build_kb;

/// Permanent harness for actually running `build_kb.dart`'s `main()`.
///
/// `EmbeddingService` loads its ONNX model and vocab via `rootBundle`, which
/// needs a Flutter engine (`dart:ui`) — unavailable to a bare
/// `dart run tool/build_kb.dart`. This
/// hosts the exact same, unmodified `build_kb.main()` under `flutter test`,
/// which does provide those bindings. No product code is changed to work
/// around this; it's purely an invocation mechanism.
///
/// Usage:
///   flutter test tool/build_kb_runner.dart --timeout=none \
///     --dart-define=KB_OUTPUT=path/to/kb.db --dart-define=KB_VERSION=1.0.0
void main() {
  // CRITICAL: without this, rootBundle has no ServicesBinding to talk to —
  // EmbeddingService.init() throws "Binding has not yet been initialized",
  // is caught, and silently falls back to random mock embeddings for the
  // entire build. This was missing since this harness was first written,
  // meaning every kb.db ever built by this project (through kb-v1.0.1)
  // shipped with mock, not real, embeddings — confirmed empirically: a
  // synonymous sentence pair and an unrelated pair scored nearly identical
  // near-zero cosine similarity (0.0895 vs 0.0996 — no meaningful gap,
  // consistent with random unit vectors), versus 0.756 vs 0.399 (a large,
  // meaningful gap) once this fix and the LD_LIBRARY_PATH fix in
  // .github/workflows/build-kb-on-tag.yml were both in place.
  TestWidgetsFlutterBinding.ensureInitialized();

  // TestWidgetsFlutterBinding installs a fake HttpOverrides that makes every
  // dart:io HttpClient request return a fake 400 with no real network call —
  // a deliberate safety feature for widget tests, but this script's whole
  // job is fetching real Quran/Hadith/Tafsir content over HTTP. Confirmed
  // empirically: without this line, build_kb.dart's first live request
  // fails with FormatException ("Unexpected end of input") trying to
  // jsonDecode an empty 400 body. Clearing the override restores real
  // network I/O without touching the ServicesBinding/rootBundle wiring
  // above (HttpOverrides is unrelated to that).
  HttpOverrides.global = null;

  test('build kb.db', () async {
    const output = String.fromEnvironment('KB_OUTPUT', defaultValue: 'kb.db');
    const version = String.fromEnvironment('KB_VERSION', defaultValue: '0.0.0');
    await build_kb.main(['--output', output, '--version', version]);
  });
}
