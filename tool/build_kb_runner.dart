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
  test('build kb.db', () async {
    const output = String.fromEnvironment('KB_OUTPUT', defaultValue: 'kb.db');
    const version = String.fromEnvironment('KB_VERSION', defaultValue: '0.0.0');
    await build_kb.main(['--output', output, '--version', version]);
  });
}
