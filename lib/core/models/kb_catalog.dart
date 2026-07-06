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
/// Verified against the real kb-v1.1.0 GitHub Release (2026-07-06):
/// size 536846336 bytes, sha256 8d189e81b8cf87840f6d538b0e5f75ba9a069b19924a89e66fc35b72c8f54b36.
/// v1.1.0 is the first release built with real BGE embeddings (all prior
/// releases, including v1.0.1, shipped with random mock embeddings due to
/// a build-harness bug — see tool/build_kb_runner.dart), and adds chunked
/// tafsir plus a precomputed BM25 index for hybrid retrieval
/// (see lib/data/repositories/rag_repository.dart).
const KbInfo kCurrentKb = KbInfo(
  version: '1.1.0',
  filename: 'kb.db',
  sizeBytes: 536846336,
  sha256: '8d189e81b8cf87840f6d538b0e5f75ba9a069b19924a89e66fc35b72c8f54b36',
);
