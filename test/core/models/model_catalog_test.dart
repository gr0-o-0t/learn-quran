import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/models/model_catalog.dart';

void main() {
  group('Model catalog', () {
    test('has exactly two entries: e2b and e4b', () {
      expect(kModelCatalog.length, 2);
      expect(kModelCatalog.map((m) => m.id), containsAll(['e2b', 'e4b']));
    });

    test('downloadUrl builds the correct Hugging Face resolve URL', () {
      final e2b = modelById('e2b');
      expect(
        e2b.downloadUrl,
        'https://huggingface.co/${e2b.huggingFaceRepo}/resolve/main/${e2b.filename}',
      );
    });

    test('modelById returns the matching entry', () {
      expect(modelById('e4b').id, 'e4b');
    });

    test('modelById falls back to the first entry for an unknown id', () {
      expect(modelById('nonexistent').id, kModelCatalog.first.id);
    });

    test('recommendedModelFor picks e2b below the e4b RAM threshold', () {
      expect(recommendedModelFor(4.0).id, 'e2b');
      expect(recommendedModelFor(5.9).id, 'e2b');
    });

    test('recommendedModelFor picks e4b at or above its RAM threshold', () {
      expect(recommendedModelFor(6.0).id, 'e4b');
      expect(recommendedModelFor(12.0).id, 'e4b');
    });
  });
}
