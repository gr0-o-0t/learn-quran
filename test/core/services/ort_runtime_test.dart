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
