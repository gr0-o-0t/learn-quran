import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/models/kb_catalog.dart';

void main() {
  test('kCurrentKb has a well-formed GitHub release download URL', () {
    expect(kCurrentKb.downloadUrl, contains('github.com'));
    expect(kCurrentKb.downloadUrl, contains(kCurrentKb.version));
    expect(kCurrentKb.downloadUrl, endsWith(kCurrentKb.filename));
  });

  test('kCurrentKb.sizeBytes is filled in with the real published size', () {
    expect(kCurrentKb.sizeBytes, 259268608);
  });

  test('kCurrentKb.sha256 is a well-formed, correct 64-char lowercase hex digest', () {
    expect(kCurrentKb.sha256, hasLength(64));
    expect(kCurrentKb.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(
      kCurrentKb.sha256,
      '517dffad618e75fa226a471e873cdd5a1f7fc46d78b7c7025760cf1d4803246b',
    );
  });
}
