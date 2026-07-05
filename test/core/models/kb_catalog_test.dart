import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/models/kb_catalog.dart';

void main() {
  test('kCurrentKb has a well-formed GitHub release download URL', () {
    expect(kCurrentKb.downloadUrl, contains('github.com'));
    expect(kCurrentKb.downloadUrl, contains(kCurrentKb.version));
    expect(kCurrentKb.downloadUrl, endsWith(kCurrentKb.filename));
  });

  test(
    'kCurrentKb.sizeBytes is filled in with the real published size',
    () {
      expect(
        kCurrentKb.sizeBytes,
        greaterThan(0),
        reason: 'Run Task 10 (cut the kb-v1.0.0 release) and hardcode the '
            'real byte count here — see kb_catalog.dart\'s TODO.',
      );
    },
    skip: 'Intentionally skipped until Task 10 publishes a real kb-v1.0.0 release.',
  );
}
