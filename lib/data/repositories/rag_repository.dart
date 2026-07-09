import 'dart:math';
import 'dart:typed_data';
import '../local/db/knowledge_base_database.dart';
import '../../core/services/embedding_service.dart';
import '../../core/services/bm25_index.dart';
import '../../core/services/reranker_service.dart';
import '../../core/theme/quran_data.dart';
import '../../core/utils/embedding_quantization.dart';

enum RagSourceType { verse, hadith, tafsir }

class RagSearchResult {
  final RagSourceType type;
  final double score;
  final Verse? verse;
  final Hadith? hadith;
  final TafsirChunk? tafsir;

  RagSearchResult({
    required this.type,
    required this.score,
    this.verse,
    this.hadith,
    this.tafsir,
  });
}

/// A citation ready for display or for inclusion in an LLM prompt.
class RagCitation {
  final String title;
  final String text;
  const RagCitation({required this.title, required this.text});
}

/// English name for surah [number] (1-114), e.g. 'Al-Fatiha'. Falls back to
/// the bare number if it's out of range (shouldn't happen with real KB data).
String _surahName(int number) {
  if (number < 1 || number > quranSurahs.length) return '$number';
  return quranSurahs[number - 1]['nameEn'] as String;
}

/// Builds the citation label/text for a [RagSearchResult] — shared by the UI
/// (citation chips, qa_agent_screen.dart) and LlmService (the "Reference
/// material" it grounds answers in), so the two can never drift out of sync.
RagCitation citationFor(RagSearchResult result) {
  switch (result.type) {
    case RagSourceType.verse:
      final verse = result.verse!;
      return RagCitation(
        title: 'Surah ${_surahName(verse.surahNumber)} ${verse.surahNumber}:${verse.ayahNumber}',
        text: verse.englishText,
      );
    case RagSourceType.hadith:
      final hadith = result.hadith!;
      return RagCitation(
        title: '${hadith.bookName} Hadith ${hadith.hadithNumber}',
        text: hadith.englishText,
      );
    case RagSourceType.tafsir:
      final tafsir = result.tafsir!;
      return RagCitation(
        title: 'Tafsir ${_surahName(tafsir.surahNumber)} ${tafsir.surahNumber}:${tafsir.ayahNumber}',
        text: tafsir.contentEnglish,
      );
  }
}

/// Hybrid retrieval over the offline knowledge base: fuses embedding
/// similarity (an in-memory, SIMD-accelerated scan — see [_ensureEmbeddingCache])
/// with BM25 keyword search ([Bm25Index]) via Reciprocal Rank Fusion.
class RagRepository {
  final KnowledgeBaseDatabase _db;
  final EmbeddingService _embeddingService;
  final RerankerService _rerankerService;
  late final Bm25Index _bm25Index;

  static const int hadithOffset = 100000;
  static const int tafsirOffset = 200000;
  static const int _embeddingDimensions = 384;
  static const int _rrfK = 60;
  static const int _rerankCandidateCount = 20;

  Int8List? _embeddingMatrix;
  List<int>? _embeddingDocIds;

  RagRepository(this._db, this._embeddingService, [RerankerService? rerankerService])
      : _rerankerService = rerankerService ?? RerankerService() {
    _bm25Index = Bm25Index(_db);
  }

  /// Loads every stored embedding into one flat, contiguous [Float32List]
  /// (docCount × 384) plus a parallel doc-id list, once. Replaces the old
  /// per-query `SELECT * FROM vec_knowledge_base` (the dominant cost of the
  /// previous implementation) — this cache lives for the repository's
  /// lifetime, which is naturally rebuilt whenever the KB is re-downloaded
  /// (see database_provider.dart's ref.invalidate wiring).
  Future<void> _ensureEmbeddingCache() async {
    if (_embeddingMatrix != null) return;

    final rows = await _db.customSelect('SELECT rowid, embedding FROM vec_knowledge_base').get();
    final docIds = <int>[];
    final matrix = Int8List(rows.length * _embeddingDimensions);

    for (var i = 0; i < rows.length; i++) {
      final rowid = rows[i].read<int>('rowid');
      final blob = rows[i].read<Uint8List>('embedding');
      final int8s = Int8List.sublistView(blob);
      docIds.add(rowid);
      final offset = i * _embeddingDimensions;
      final count = min(_embeddingDimensions, int8s.length);
      for (var d = 0; d < count; d++) {
        matrix[offset + d] = int8s[d];
      }
    }

    _embeddingDocIds = docIds;
    _embeddingMatrix = matrix;
  }

  /// Integer dot product between [query] and the doc embedding stored at
  /// [docIndex] in [matrix]. Both are int8-quantized (see
  /// core/utils/embedding_quantization.dart) — Dart's `dart:typed_data` has
  /// no int8 SIMD type, so this is a plain scalar loop; at this corpus size
  /// (tens of thousands of docs) that's expected to still be fast enough on
  /// a phone CPU (see the design doc's A1/A3 assumptions) without needing
  /// the Float32x4 SIMD the old float32 version used.
  int _dotProductInt8(Int8List query, Int8List matrix, int docIndex) {
    final base = docIndex * _embeddingDimensions;
    var sum = 0;
    for (var d = 0; d < _embeddingDimensions; d++) {
      sum += query[d] * matrix[base + d];
    }
    return sum;
  }

  Future<List<MapEntry<int, double>>> _embeddingSearch(String query, {int limit = 20}) async {
    await _ensureEmbeddingCache();
    final docIds = _embeddingDocIds!;
    final matrix = _embeddingMatrix!;
    if (docIds.isEmpty) return const [];

    final queryVector = await _embeddingService.getEmbedding(query, isQuery: true);
    final queryInt8 = quantizeVector(queryVector);

    final scored = <MapEntry<int, double>>[];
    for (var i = 0; i < docIds.length; i++) {
      scored.add(MapEntry(docIds[i], _dotProductInt8(queryInt8, matrix, i).toDouble()));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).toList();
  }

  /// Fuses two ranked (docId, score) lists via Reciprocal Rank Fusion —
  /// score depends only on rank position, so BM25 scores and dot-product
  /// scores never need to be rescaled against each other. A doc present in
  /// only one list still accumulates a score from that list alone.
  List<MapEntry<int, double>> _reciprocalRankFusion(
    List<MapEntry<int, double>> a,
    List<MapEntry<int, double>> b, {
    required int limit,
  }) {
    final fused = <int, double>{};
    for (var rank = 0; rank < a.length; rank++) {
      final docId = a[rank].key;
      fused[docId] = (fused[docId] ?? 0) + 1 / (_rrfK + rank + 1);
    }
    for (var rank = 0; rank < b.length; rank++) {
      final docId = b[rank].key;
      fused[docId] = (fused[docId] ?? 0) + 1 / (_rrfK + rank + 1);
    }
    final ranked = fused.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
    return ranked.take(limit).toList();
  }

  /// Hybrid retrieval: fuses embedding similarity with BM25 keyword search,
  /// then hydrates the fused top-[limit] ids into full verse/hadith/
  /// tafsir-chunk rows.
  Future<List<RagSearchResult>> search(String query, {int limit = 5}) async {
    final embeddingResults = await _embeddingSearch(query, limit: 20);
    final bm25Results = await _bm25Index.search(query, limit: 20);
    final fused = _reciprocalRankFusion(embeddingResults, bm25Results, limit: _rerankCandidateCount);

    final candidates = <RagSearchResult>[];
    for (final entry in fused) {
      final match = await _buildSearchResult(entry.key, entry.value);
      if (match.verse != null || match.hadith != null || match.tafsir != null) {
        candidates.add(match);
      }
    }

    final reranked = await _rerank(query, candidates);
    return reranked.take(limit).toList();
  }

  /// Reranks [candidates] by relevance to [query] using [_rerankerService],
  /// highest score first. If the reranker is unavailable or any single
  /// scoring call fails, bails out to the original (RRF-fused) order for
  /// every candidate — reranking either fully succeeds or is fully skipped,
  /// never partially applied.
  Future<List<RagSearchResult>> _rerank(String query, List<RagSearchResult> candidates) async {
    if (candidates.isEmpty) return candidates;

    final scored = <MapEntry<RagSearchResult, double>>[];
    for (final candidate in candidates) {
      final text = citationFor(candidate).text;
      final score = await _rerankerService.score(query, text);
      if (score == null) return candidates;
      scored.add(MapEntry(candidate, score));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }

  Future<RagSearchResult> _buildSearchResult(int rowid, double score) async {
    if (rowid < hadithOffset) {
      final verse = await (_db.select(_db.verses)..where((t) => t.id.equals(rowid))).getSingleOrNull();
      return RagSearchResult(type: RagSourceType.verse, score: score, verse: verse);
    } else if (rowid >= hadithOffset && rowid < tafsirOffset) {
      final hadithId = rowid - hadithOffset;
      final hadith = await (_db.select(_db.hadiths)..where((t) => t.id.equals(hadithId))).getSingleOrNull();
      return RagSearchResult(type: RagSourceType.hadith, score: score, hadith: hadith);
    } else {
      final tafsirChunkId = rowid - tafsirOffset;
      final tafsirChunk =
          await (_db.select(_db.tafsirChunks)..where((t) => t.id.equals(tafsirChunkId))).getSingleOrNull();
      return RagSearchResult(type: RagSourceType.tafsir, score: score, tafsir: tafsirChunk);
    }
  }
}
