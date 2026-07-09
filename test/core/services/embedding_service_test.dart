import 'package:flutter_test/flutter_test.dart';
import 'package:bert_tokenizer/bert_tokenizer.dart';
import 'package:learn_quran/core/services/embedding_service.dart';
import 'package:learn_quran/core/services/ort_runtime.dart';

const _miniVocab = '''
[PAD]
[UNK]
[CLS]
[SEP]
patience
is
a
virtue
##ness
allah
''';

void main() {
  group('BertTokenizer (real WordPiece, not the old fake char-code one)', () {
    test('tokenizes known words into the expected vocab ids', () {
      final tokenizer = BertTokenizer.fromStringContent(_miniVocab);
      final input = tokenizer.prepareNerInput('patience is a virtue', 16);

      // [CLS] patience is a virtue [SEP] ... padded to 16
      expect(input.inputIds[0], 2); // [CLS]
      expect(input.inputIds[1], 4); // patience
      expect(input.inputIds[2], 5); // is
      expect(input.inputIds[3], 6); // a
      expect(input.inputIds[4], 7); // virtue
      expect(input.inputIds[5], 3); // [SEP]
      expect(input.inputIds.length, 16);
      expect(input.inputMask[0], 1);
      expect(input.inputMask.last, 0); // padding
    });

    test('falls back to [UNK] for words not in the vocab', () {
      final tokenizer = BertTokenizer.fromStringContent(_miniVocab);
      final tokens = tokenizer.tokenize('zzzznotarealword');
      expect(tokens, contains('[UNK]'));
    });
  });

  group('EmbeddingService', () {
    setUp(() {
      // Reset OrtRuntime's ref count before each test so tests don't interfere.
      OrtRuntime.resetForTesting();
    });

    test('normalized mock embedding has unit length (fallback path, no model files)', () async {
      final service = EmbeddingService(forceMock: true);
      final embedding = await service.getEmbedding('test text');
      final normSquared = embedding.fold<double>(0, (sum, v) => sum + v * v);
      expect(normSquared, closeTo(1.0, 1e-6));
    });

    test('query and passage embeddings differ when isQuery changes the input text', () async {
      // With the mock path (no real ONNX model in the test environment),
      // the query prefix still changes the string that gets hashed, so the
      // two mock embeddings for the same base text must differ.
      final service = EmbeddingService(forceMock: true);
      final passage = await service.getEmbedding('patience in Islam');
      final query = await service.getEmbedding('patience in Islam', isQuery: true);
      expect(passage, isNot(equals(query)));
    });

    test('releases OrtRuntime ref count on init failure (no ONNX assets in test env)',
        () async {
      // Regression test for: https://github.com/learn-quran/mobile-rag-optimization/issues/X
      // When init() fails after calling OrtRuntime.acquire(), the catch block
      // must call OrtRuntime.release() to balance the acquire. Otherwise,
      // the ref count stays inflated and real embeddings silently degrade to
      // random noise (dispose() never calls release() for a fallen-back-to-mock
      // instance because of the !_useMock guard).

      // Create a real (non-mock) EmbeddingService. Since the test environment
      // has no ONNX assets, init() will fail to load them and fall through to
      // the catch block — exactly the path this fix addresses.
      final service = EmbeddingService();
      await service.init();

      // If OrtRuntime.release() was NOT called in the catch block, the ref
      // count would still be 1, and this fresh acquire() would NOT call the
      // initFn (since _refCount != 0). But if release() was called correctly,
      // the ref count should be back to 0, and acquire() WILL call the initFn.
      var initWasCalled = false;
      OrtRuntime.acquire(initFn: () {
        initWasCalled = true;
      });

      // Verify the ref count is back to zero by checking if initFn was called.
      expect(initWasCalled, isTrue, reason: 'initFn should have been called since ref count was at zero after init() failure');

      // Clean up the acquire we just made (with a no-op release to avoid
      // invoking the real native ONNX environment in the test).
      OrtRuntime.release(releaseFn: () {});
    });
  });
}
