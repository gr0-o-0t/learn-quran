/// A downloadable, versioned knowledge base release.
class KbInfo {
  final String version;
  final String filename;
  final int sizeBytes;
  final String sha256;

  const KbInfo({
    required this.version,
    required this.filename,
    required this.sizeBytes,
    required this.sha256,
  });

  String get downloadUrl =>
      'https://github.com/gr0-o-0t/learn-quran/releases/download/kb-v$version/$filename';
}

/// The current knowledge base version the app knows how to fetch.
/// Verified against the real kb-v1.0.1 GitHub Release (2026-07-05):
/// size 259268608 bytes, sha256 517dffad618e75fa226a471e873cdd5a1f7fc46d78b7c7025760cf1d4803246b.
/// v1.0.1 drops the ~212 hadith rows with no upstream English text that
/// v1.0.0 shipped with blank englishText (see tool/build_kb.dart).
const KbInfo kCurrentKb = KbInfo(
  version: '1.0.1',
  filename: 'kb.db',
  sizeBytes: 259268608,
  sha256: '517dffad618e75fa226a471e873cdd5a1f7fc46d78b7c7025760cf1d4803246b',
);
