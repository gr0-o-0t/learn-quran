import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/models/kb_catalog.dart';

void main() {
  test('kCurrentKb has a well-formed GitHub release download URL', () {
    expect(kCurrentKb.downloadUrl, contains('github.com'));
    expect(kCurrentKb.downloadUrl, contains(kCurrentKb.version));
    expect(kCurrentKb.downloadUrl, endsWith(kCurrentKb.filename));
  });

  test('kCurrentKb.sizeBytes is filled in with the real published size', () {
    expect(kCurrentKb.sizeBytes, 536846336);
  });

  test('kCurrentKb.sha256 is a well-formed, correct 64-char lowercase hex digest', () {
    expect(kCurrentKb.sha256, hasLength(64));
    expect(kCurrentKb.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(
      kCurrentKb.sha256,
      '8d189e81b8cf87840f6d538b0e5f75ba9a069b19924a89e66fc35b72c8f54b36',
    );
  });
}
