import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/models/model_catalog.dart';

void main() {
  group('Model catalog', () {
    test('has exactly three entries: tiny, e2b, and e4b', () {
      expect(kModelCatalog.length, 3);
      expect(kModelCatalog.map((m) => m.id), containsAll(['tiny', 'e2b', 'e4b']));
    });

    test('downloadUrl builds the correct Hugging Face resolve URL', () {
      final e2b = modelById('e2b');
      expect(
        e2b.downloadUrl,
        'https://huggingface.co/${e2b.huggingFaceRepo}/resolve/${e2b.revision}/${e2b.filename}',
      );
    });

    test('modelById returns the matching entry', () {
      expect(modelById('e4b').id, 'e4b');
      expect(modelById('tiny').id, 'tiny');
    });

    test('modelById falls back to the first entry for an unknown id', () {
      expect(modelById('nonexistent').id, kModelCatalog.first.id);
    });

    test('recommendedModelFor picks tiny below the e2b RAM threshold', () {
      expect(recommendedModelFor(2.0).id, 'tiny');
      expect(recommendedModelFor(3.9).id, 'tiny');
    });

    test('recommendedModelFor picks e2b between the e2b and e4b RAM thresholds', () {
      expect(recommendedModelFor(4.0).id, 'e2b');
      expect(recommendedModelFor(5.9).id, 'e2b');
    });

    test('recommendedModelFor picks e4b at or above its RAM threshold', () {
      expect(recommendedModelFor(6.0).id, 'e4b');
      expect(recommendedModelFor(12.0).id, 'e4b');
    });
  });
}
