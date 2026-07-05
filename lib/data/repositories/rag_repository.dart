import 'dart:typed_data';
import '../local/db/knowledge_base_database.dart';
import '../../core/services/embedding_service.dart';

enum RagSourceType { verse, hadith, tafsir }

class RagSearchResult {
  final RagSourceType type;
  final double score;
  final Verse? verse;
  final Hadith? hadith;
  final Tafsir? tafsir;

  RagSearchResult({
    required this.type,
    required this.score,
    this.verse,
    this.hadith,
    this.tafsir,
  });
}

class RagRepository {
  final KnowledgeBaseDatabase _db;
  final EmbeddingService _embeddingService;

  static const int hadithOffset = 100000;
  static const int tafsirOffset = 200000;

  RagRepository(this._db, this._embeddingService);

  /// Performs vector similarity search. Returns top k matches.
  Future<List<RagSearchResult>> search(String query, {int limit = 5}) async {
    final queryVector = await _embeddingService.getEmbedding(query, isQuery: true);

    final allRows = await _db.customSelect('SELECT rowid, embedding FROM vec_knowledge_base').get();
    final scoredRows = <_ScoredRow>[];

    for (final row in allRows) {
      final rowid = row.read<int>('rowid');
      final blob = row.read<Uint8List>('embedding');
      final floatList = Float32List.sublistView(blob);

      double score = 0.0;
      final minLength = queryVector.length < floatList.length ? queryVector.length : floatList.length;
      for (int i = 0; i < minLength; i++) {
        score += queryVector[i] * floatList[i];
      }

      scoredRows.add(_ScoredRow(rowid, score));
    }

    scoredRows.sort((a, b) => b.score.compareTo(a.score));
    final topRows = scoredRows.take(limit);

    final searchResults = <RagSearchResult>[];
    for (final row in topRows) {
      final match = await _buildSearchResult(row.rowid, row.score);
      if (match.verse != null || match.hadith != null || match.tafsir != null) {
        searchResults.add(match);
      }
    }

    return searchResults;
  }

  Future<RagSearchResult> _buildSearchResult(int rowid, double score) async {
    if (rowid < hadithOffset) {
      final verse = await (_db.select(_db.verses)..where((t) => t.id.equals(rowid))).getSingleOrNull();
      return RagSearchResult(
        type: RagSourceType.verse,
        score: score,
        verse: verse,
      );
    } else if (rowid >= hadithOffset && rowid < tafsirOffset) {
      final hadithId = rowid - hadithOffset;
      final hadith = await (_db.select(_db.hadiths)..where((t) => t.id.equals(hadithId))).getSingleOrNull();
      return RagSearchResult(
        type: RagSourceType.hadith,
        score: score,
        hadith: hadith,
      );
    } else {
      final tafsirId = rowid - tafsirOffset;
      final tafsir = await (_db.select(_db.tafsirs)..where((t) => t.id.equals(tafsirId))).getSingleOrNull();
      return RagSearchResult(
        type: RagSourceType.tafsir,
        score: score,
        tafsir: tafsir,
      );
    }
  }
}

class _ScoredRow {
  final int rowid;
  final double score;
  _ScoredRow(this.rowid, this.score);
}
