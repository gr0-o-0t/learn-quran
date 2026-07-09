import 'dart:typed_data';

/// Fixed-scale int8 quantization for L2-normalized embedding vectors.
/// `EmbeddingService.getEmbedding` always returns a unit-length vector, so
/// every component is bounded to `[-1, 1]` — a fixed scale (mapping to the
/// signed int8 range, -127..127) needs no per-vector min/max, unlike
/// general-purpose quantization schemes over unbounded values.
const int quantizationScale = 127;

int quantizeComponent(double value) {
  final scaled = (value * quantizationScale).round();
  if (scaled > quantizationScale) return quantizationScale;
  if (scaled < -quantizationScale) return -quantizationScale;
  return scaled;
}

Int8List quantizeVector(List<double> vector) {
  final result = Int8List(vector.length);
  for (var i = 0; i < vector.length; i++) {
    result[i] = quantizeComponent(vector[i]);
  }
  return result;
}
