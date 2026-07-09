import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/utils/embedding_quantization.dart';

void main() {
  group('quantizeComponent', () {
    test('maps 1.0 to the max int8 scale value', () {
      expect(quantizeComponent(1.0), 127);
    });

    test('maps -1.0 to the min representable value', () {
      expect(quantizeComponent(-1.0), -127);
    });

    test('maps 0.0 to 0', () {
      expect(quantizeComponent(0.0), 0);
    });

    test('clamps values that round outside the int8 range', () {
      expect(quantizeComponent(1.5), 127);
      expect(quantizeComponent(-1.5), -127);
    });

    test('rounds to the nearest integer', () {
      expect(quantizeComponent(0.6), 76); // round(0.6 * 127) = round(76.2) = 76
    });
  });

  group('quantizeVector', () {
    test('quantizes every component and preserves length', () {
      final result = quantizeVector([1.0, -1.0, 0.0, 0.6]);
      expect(result.length, 4);
      expect(result[0], 127);
      expect(result[1], -127);
      expect(result[2], 0);
      expect(result[3], 76);
    });

    test('returns an empty Int8List for an empty vector', () {
      expect(quantizeVector([]).length, 0);
    });
  });
}
