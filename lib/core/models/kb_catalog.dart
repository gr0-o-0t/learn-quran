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
/// Verified against the real kb-v1.2.0 GitHub Release (2026-07-10):
/// size 384888832 bytes, sha256 8b3522797c832e661e74688d37116d91bb9bee0f67f8aabf48d34a21842cd02d.
/// v1.2.0 int8-quantizes the embedding vectors (4x smaller than v1.1.0's
/// float32 storage) and dictionary-encodes BM25 postings (a new
/// Bm25Terms table, replacing per-posting term strings with integer
/// termIds) — together shrinking the file by ~28% vs v1.1.0's 536846336
/// bytes, as part of a mobile RAG optimization round (see
/// lib/data/repositories/rag_repository.dart, lib/core/utils/embedding_quantization.dart).
const KbInfo kCurrentKb = KbInfo(
  version: '1.2.0',
  filename: 'kb.db',
  sizeBytes: 384888832,
  sha256: '8b3522797c832e661e74688d37116d91bb9bee0f67f8aabf48d34a21842cd02d',
);
