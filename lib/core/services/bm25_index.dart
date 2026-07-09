import 'dart:math';
import '../../data/local/db/knowledge_base_database.dart';
import '../utils/bm25_tokenizer.dart';

const _k1 = 1.2;
const _b = 0.75;

/// Ranks documents by BM25 lexical relevance against a query, using the
/// term-frequency/document-length statistics tool/build_kb.dart precomputes
/// into `Bm25Postings`/`Bm25DocStats`/`KbMeta` at build time.
class Bm25Index {
  final KnowledgeBaseDatabase _db;
  const Bm25Index(this._db);

  /// Returns up to [limit] (docId, score) pairs, highest score first.
  /// Returns an empty list — never throws — if the query has no indexable
  /// terms, if BM25 metadata hasn't been populated (a fresh/empty KB), or if
  /// the KB predates the BM25 tables entirely (an older kb.db) — callers
  /// should treat all of these exactly like "no keyword matches" rather
  /// than a hard failure.
  Future<List<MapEntry<int, double>>> search(String query, {int limit = 20}) async {
    final terms = tokenizeForBm25(query).toSet();
    if (terms.isEmpty) return const [];

    try {
      final docCountRow =
          await (_db.select(_db.kbMeta)..where((t) => t.key.equals('bm25_doc_count'))).getSingleOrNull();
      final avgLengthRow =
          await (_db.select(_db.kbMeta)..where((t) => t.key.equals('bm25_avg_doc_length'))).getSingleOrNull();
      if (docCountRow == null || avgLengthRow == null) return const [];
      final docCount = int.parse(docCountRow.value);
      final avgDocLength = double.parse(avgLengthRow.value);
      if (docCount == 0 || avgDocLength == 0) return const [];

      final scores = <int, double>{};
      for (final term in terms) {
        final termRow = await (_db.select(_db.bm25Terms)..where((t) => t.term.equals(term))).getSingleOrNull();
        if (termRow == null) continue; // term not in the dictionary — no matches for it
        final postings = await (_db.select(_db.bm25Postings)..where((t) => t.termId.equals(termRow.termId))).get();
        if (postings.isEmpty) continue;

        final df = postings.length;
        final idf = log((docCount - df + 0.5) / (df + 0.5) + 1);

        final docIds = postings.map((p) => p.docId).toList();
        final statsRows = await (_db.select(_db.bm25DocStats)..where((t) => t.docId.isIn(docIds))).get();
        final lengthByDocId = {for (final row in statsRows) row.docId: row.docLength};

        for (final posting in postings) {
          final docLength = lengthByDocId[posting.docId] ?? avgDocLength.round();
          final tf = posting.termFrequency;
          final denom = tf + _k1 * (1 - _b + _b * docLength / avgDocLength);
          scores[posting.docId] = (scores[posting.docId] ?? 0) + idf * (tf * (_k1 + 1)) / denom;
        }
      }

      final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return sorted.take(limit).toList();
    } catch (_) {
      return const [];
    }
  }
}
