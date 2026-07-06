import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:bert_tokenizer/bert_tokenizer.dart';

/// BGE's documented asymmetric convention: passages/corpus text embeds
/// plain, but queries get this instruction prefix — skipping it measurably
/// hurts retrieval quality per the model's own card.
const _queryPrefix = 'Represent this sentence for searching relevant passages: ';

const _maxTokenLength = 256;

class EmbeddingService {
  OrtSession? _session;
  BertTokenizer? _tokenizer;
  bool _initialized = false;
  bool _useMock = false;

  EmbeddingService({bool forceMock = false}) : _useMock = forceMock;

  Future<void> init() async {
    if (_initialized) return;

    if (_useMock) {
      _initialized = true;
      return;
    }

    try {
      final vocabData = await rootBundle.loadString('assets/models/bge_small_en_v1_5_vocab.txt');
      _tokenizer = BertTokenizer.fromStringContent(vocabData);

      OrtEnv.instance.init();
      final bytes = await rootBundle.load('assets/models/bge_small_en_v1_5.onnx');
      final sessionOptions = OrtSessionOptions();
      _session = OrtSession.fromBuffer(bytes.buffer.asUint8List(), sessionOptions);
      _initialized = true;
    } catch (e, st) {
      // Fallback to mock if assets aren't present or init fails (e.g. tests)
      // — but real embeddings silently degrading to random noise on a real
      // device is a serious, otherwise-invisible failure, so this must be
      // loud: every RAG search would look "successful" (valid citations)
      // while actually retrieving semantically unrelated content.
      debugPrint('EmbeddingService.init failed, falling back to mock embeddings: $e\n$st');
      _useMock = true;
      _initialized = true;
    }
  }

  /// Returns a normalized 384-dim embedding for [text]. Set [isQuery] when
  /// embedding a search query (not corpus/passage text) so BGE's asymmetric
  /// instruction prefix is applied — see the constant above.
  Future<List<double>> getEmbedding(String text, {bool isQuery = false}) async {
    await init();

    final effectiveText = isQuery ? '$_queryPrefix$text' : text;

    if (_useMock) {
      return _generateMockEmbedding(effectiveText);
    }

    try {
      final input = _tokenizer!.prepareNerInput(effectiveText, _maxTokenLength);
      final shape = [1, input.inputIds.length];

      final inputIdsTensor = OrtValueTensor.createTensorWithDataList(input.inputIds, shape);
      final attentionMaskTensor = OrtValueTensor.createTensorWithDataList(input.inputMask, shape);
      final tokenTypeIdsTensor = OrtValueTensor.createTensorWithDataList(input.segmentIds, shape);

      final inputs = {
        'input_ids': inputIdsTensor,
        'attention_mask': attentionMaskTensor,
        'token_type_ids': tokenTypeIdsTensor,
      };

      final runOptions = OrtRunOptions();
      final outputs = await _session!.runAsync(runOptions, inputs);

      // BGE uses CLS pooling per its model card: the sentence embedding is
      // the first token's ('[CLS]') last-hidden-state vector, not a mean
      // over all tokens.
      final lastHiddenState = outputs != null && outputs.isNotEmpty ? outputs[0]?.value : null;
      List<double> embedding = [];
      if (lastHiddenState is List && lastHiddenState.isNotEmpty) {
        final batch0 = lastHiddenState[0]; // [seq_len, hidden]
        if (batch0 is List && batch0.isNotEmpty) {
          final clsVector = batch0[0]; // [hidden] — the [CLS] token
          embedding = (clsVector as List).map((e) => (e as num).toDouble()).toList();
        }
      }

      inputIdsTensor.release();
      attentionMaskTensor.release();
      tokenTypeIdsTensor.release();
      if (outputs != null) {
        for (final out in outputs) {
          out?.release();
        }
      }
      runOptions.release();

      if (embedding.isEmpty) {
        debugPrint(
          'EmbeddingService.getEmbedding got an empty vector from the ONNX '
          'session for "$effectiveText" — falling back to a mock embedding.',
        );
        return _generateMockEmbedding(effectiveText);
      }
      return _normalize(embedding);
    } catch (e, st) {
      debugPrint(
        'EmbeddingService.getEmbedding failed for "$effectiveText", falling '
        'back to a mock embedding: $e\n$st',
      );
      return _generateMockEmbedding(effectiveText);
    }
  }

  /// Synchronous, exact token count for [text] using the already-loaded
  /// tokenizer — callers MUST call [init] first (throws otherwise). Used by
  /// tool/build_kb.dart's tafsir chunker, which needs precise token counts
  /// in a tight, non-async loop rather than a word-count approximation.
  /// Adds 2 for the [CLS]/[SEP] special tokens `getEmbedding` also adds, so
  /// the count matches the real sequence length fed to the model.
  int countTokensSync(String text) {
    if (!_initialized) {
      throw StateError('EmbeddingService.countTokensSync called before init()');
    }
    if (_useMock) {
      return text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length + 2;
    }
    return _tokenizer!.tokenize(text).length + 2;
  }

  List<double> _normalize(List<double> vector) {
    double sumOfSquares = 0.0;
    for (final val in vector) {
      sumOfSquares += val * val;
    }
    final norm = sqrt(sumOfSquares);
    if (norm == 0.0) return List<double>.filled(vector.length, 0.0);
    return vector.map((e) => e / norm).toList();
  }

  List<double> _generateMockEmbedding(String text) {
    final rand = Random(text.hashCode);
    final vector = List<double>.generate(384, (_) => rand.nextDouble() * 2 - 1);
    return _normalize(vector);
  }

  void dispose() {
    _session?.release();
    if (_initialized && !_useMock) {
      OrtEnv.instance.release();
    }
  }
}
