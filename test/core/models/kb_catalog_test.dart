import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/models/kb_catalog.dart';

void main() {
  test('kCurrentKb has a well-formed GitHub release download URL', () {
    expect(kCurrentKb.downloadUrl, contains('github.com'));
    expect(kCurrentKb.downloadUrl, contains(kCurrentKb.version));
    expect(kCurrentKb.downloadUrl, endsWith(kCurrentKb.filename));
  });

  test('kCurrentKb.sizeBytes is filled in with the real published size', () {
    expect(kCurrentKb.sizeBytes, 384888832);
  });

  test('kCurrentKb.sha256 is a well-formed, correct 64-char lowercase hex digest', () {
    expect(kCurrentKb.sha256, hasLength(64));
    expect(kCurrentKb.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(
      kCurrentKb.sha256,
      '8b3522797c832e661e74688d37116d91bb9bee0f67f8aabf48d34a21842cd02d',
    );
  });
}
