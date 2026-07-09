import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:bert_tokenizer/bert_tokenizer.dart';
import 'ort_runtime.dart';

const _maxTokenLength = 256;

/// Test/override seam: bypasses the real ONNX model entirely — used by
/// tests that want to control exactly what score a given (query, passage)
/// pair gets, without a real model file in the test environment.
typedef RerankScoreFn = Future<double?> Function(String query, String passage);

/// Scores how relevant a (query, passage) pair is, using a small on-device
/// cross-encoder (Xenova/ms-marco-MiniLM-L-6-v2, int8 ONNX, ~23MB) — used
/// by RagRepository to reorder its fused RRF candidates before truncating
/// to the final result count, since RRF fusion alone does not directly
/// model query-passage relevance the way a cross-encoder does.
class RerankerService {
  OrtSession? _session;
  BertTokenizer? _tokenizer;
  Map<String, int>? _vocabIndex;
  bool _initialized = false;
  bool _useMock = false;
  final RerankScoreFn? _scoreOverride;

  RerankerService({bool forceMock = false, RerankScoreFn? scoreOverride})
      : _useMock = forceMock,
        _scoreOverride = scoreOverride;

  Future<void> init() async {
    if (_initialized) return;

    if (_useMock) {
      _initialized = true;
      return;
    }

    try {
      // Reuses the embedding model's own vocab.txt — verified byte-
      // identical to this reranker's vocab (both are standard
      // BERT-base-uncased WordPiece vocabularies), so no second vocab
      // asset is bundled.
      final vocabData = await rootBundle.loadString('assets/models/bge_small_en_v1_5_vocab.txt');
      _tokenizer = BertTokenizer.fromStringContent(vocabData);
      _vocabIndex = _buildVocabIndex(vocabData);

      OrtRuntime.acquire();
      final bytes = await rootBundle.load('assets/models/ms_marco_minilm_l6_v2.onnx');
      final sessionOptions = OrtSessionOptions();
      _session = OrtSession.fromBuffer(bytes.buffer.asUint8List(), sessionOptions);
      _initialized = true;
    } catch (e, st) {
      // Fallback to "unavailable" (score() returns null) if assets aren't
      // present or init fails — unlike EmbeddingService, there is no
      // meaningful "mock score" to fall back to, so callers must skip
      // reranking entirely on this signal, not treat it as a real result.
      debugPrint('RerankerService.init failed, reranking will be skipped: $e\n$st');
      _useMock = true;
      _initialized = true;
    }
  }

  /// Parses the same `vocab.txt` line-per-token format
  /// `BertTokenizer.fromStringContent` parses internally, so word-piece
  /// tokens (from the tokenizer's own public `tokenize()`) can be mapped
  /// to vocabulary ids — `BertTokenizer` has no public tokens->ids method
  /// itself (only the reverse, `convertIdsToTokens`).
  Map<String, int> _buildVocabIndex(String vocabContent) {
    final lines = vocabContent.split(RegExp(r'\r?\n'));
    final index = <String, int>{};
    var i = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      index[trimmed] = i;
      i++;
    }
    return index;
  }

  /// Returns a relevance score for (query, passage) — higher means more
  /// relevant — or `null` if the reranker is unavailable (forceMock, init
  /// failure, or a scoring exception). Callers MUST treat `null` as "skip
  /// reranking for this pair", never as a real (e.g. zero or negative)
  /// score.
  Future<double?> score(String query, String passage) async {
    final scoreOverride = _scoreOverride;
    if (scoreOverride != null) return scoreOverride(query, passage);

    await init();
    if (_useMock) return null;

    try {
      final tokenizer = _tokenizer!;
      final vocabIndex = _vocabIndex!;
      final queryTokens = tokenizer.tokenize(query);
      final passageTokens = tokenizer.tokenize(passage);

      // Reserve 3 positions for [CLS] + [SEP] + [SEP]. Queries here are
      // short (a user's question); passages are the ones that can run
      // long (a full tafsir chunk), so truncate the passage, not the
      // query, when the pair doesn't fit.
      const maxContentLength = _maxTokenLength - 3;
      var truncatedQuery = queryTokens;
      if (truncatedQuery.length > maxContentLength) {
        truncatedQuery = truncatedQuery.sublist(0, maxContentLength);
      }
      final remaining = maxContentLength - truncatedQuery.length;
      var truncatedPassage = passageTokens;
      if (truncatedPassage.length > remaining) {
        truncatedPassage = truncatedPassage.sublist(0, remaining);
      }

      final tokens = [
        BertTokenizer.clsToken,
        ...truncatedQuery,
        BertTokenizer.sepToken,
        ...truncatedPassage,
        BertTokenizer.sepToken,
      ];
      final segmentIds = [
        ...List.filled(truncatedQuery.length + 2, 0), // [CLS] + query + [SEP]
        ...List.filled(truncatedPassage.length + 1, 1), // passage + [SEP]
      ];
      final unkId = vocabIndex[BertTokenizer.unkToken]!;
      final inputIds = tokens.map((t) => vocabIndex[t] ?? unkId).toList();
      final attentionMask = List<int>.filled(inputIds.length, 1);

      final shape = [1, inputIds.length];
      final inputIdsTensor = OrtValueTensor.createTensorWithDataList(inputIds, shape);
      final attentionMaskTensor = OrtValueTensor.createTensorWithDataList(attentionMask, shape);
      final tokenTypeIdsTensor = OrtValueTensor.createTensorWithDataList(segmentIds, shape);

      final inputs = {
        'input_ids': inputIdsTensor,
        'attention_mask': attentionMaskTensor,
        'token_type_ids': tokenTypeIdsTensor,
      };
      final runOptions = OrtRunOptions();
      final outputs = await _session!.runAsync(runOptions, inputs);

      // A single relevance logit per example: output shape [1, 1] (see
      // config.json's id2label — one label, not a 2-class softmax).
      double? logit;
      final rawOutput = outputs != null && outputs.isNotEmpty ? outputs[0]?.value : null;
      if (rawOutput is List && rawOutput.isNotEmpty) {
        final batch0 = rawOutput[0];
        if (batch0 is List && batch0.isNotEmpty) {
          logit = (batch0[0] as num).toDouble();
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

      if (logit == null) {
        debugPrint('RerankerService.score got no usable output for "$query" — treating as unavailable.');
      }
      return logit;
    } catch (e, st) {
      debugPrint('RerankerService.score failed for "$query": $e\n$st');
      return null;
    }
  }

  void dispose() {
    _session?.release();
    if (_initialized && !_useMock) {
      OrtRuntime.release();
    }
  }
}
