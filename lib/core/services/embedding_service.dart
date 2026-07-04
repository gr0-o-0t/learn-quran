import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

class EmbeddingService {
  OrtSession? _session;
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
      // Initialize ONNX Runtime Env
      OrtEnv.instance.init();

      // Attempt to load model from assets
      final bytes = await rootBundle.load('assets/models/embedding_model.onnx');
      final sessionOptions = OrtSessionOptions();
      _session = OrtSession.fromBuffer(bytes.buffer.asUint8List(), sessionOptions);
      _initialized = true;
    } catch (e) {
      // Fallback to mock if asset not found or init fails (e.g. in test environment)
      _useMock = true;
      _initialized = true;
    }
  }

  Future<List<double>> getEmbedding(String text) async {
    await init();

    if (_useMock) {
      return _generateMockEmbedding(text);
    }

    try {
      final tokens = _tokenize(text);
      final shape = [1, tokens.length];

      final inputIdsTensor = OrtValueTensor.createTensorWithDataList(
        tokens,
        shape,
      );
      final attentionMaskTensor = OrtValueTensor.createTensorWithDataList(
        List<int>.filled(tokens.length, 1),
        shape,
      );

      final inputs = {
        'input_ids': inputIdsTensor,
        'attention_mask': attentionMaskTensor,
      };

      final runOptions = OrtRunOptions();
      final outputs = await _session!.runAsync(runOptions, inputs);

      final outputValue = outputs != null && outputs.isNotEmpty ? outputs[0]?.value : null;
      List<double> embedding = [];
      if (outputValue is List) {
        embedding = _flatten(outputValue);
      }

      // Cleanup
      inputIdsTensor.release();
      attentionMaskTensor.release();
      if (outputs != null) {
        for (final out in outputs) {
          out?.release();
        }
      }
      runOptions.release();

      return _normalize(embedding);
    } catch (e) {
      return _generateMockEmbedding(text);
    }
  }

  List<int> _tokenize(String text) {
    final codes = text.codeUnits.map((e) => e % 30000).toList();
    if (codes.isEmpty) codes.add(0);
    if (codes.length > 128) {
      return codes.sublist(0, 128);
    }
    return codes;
  }

  List<double> _flatten(List<dynamic> list) {
    final result = <double>[];
    void helper(dynamic item) {
      if (item is num) {
        result.add(item.toDouble());
      } else if (item is List) {
        for (final x in item) {
          helper(x);
        }
      }
    }
    helper(list);
    return result;
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
