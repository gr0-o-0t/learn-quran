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
/// Verified against the real kb-v1.0.0 GitHub Release (2026-07-05):
/// size 259764224 bytes, sha256 afa19d6e5cf0b8c1d52eb4987f02ea5a3de36c184980fa82cf0e770eea9272e5.
const KbInfo kCurrentKb = KbInfo(
  version: '1.0.0',
  filename: 'kb.db',
  sizeBytes: 259764224,
  sha256: 'afa19d6e5cf0b8c1d52eb4987f02ea5a3de36c184980fa82cf0e770eea9272e5',
);
