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
