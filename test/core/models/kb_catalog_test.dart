import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/models/kb_catalog.dart';

void main() {
  test('kCurrentKb has a well-formed GitHub release download URL', () {
    expect(kCurrentKb.downloadUrl, contains('github.com'));
    expect(kCurrentKb.downloadUrl, contains(kCurrentKb.version));
    expect(kCurrentKb.downloadUrl, endsWith(kCurrentKb.filename));
  });

  test('kCurrentKb.sizeBytes is filled in with the real published size', () {
    expect(kCurrentKb.sizeBytes, 259764224);
  });

  test('kCurrentKb.sha256 is a well-formed, correct 64-char lowercase hex digest', () {
    expect(kCurrentKb.sha256, hasLength(64));
    expect(kCurrentKb.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(
      kCurrentKb.sha256,
      'afa19d6e5cf0b8c1d52eb4987f02ea5a3de36c184980fa82cf0e770eea9272e5',
    );
  });
}
