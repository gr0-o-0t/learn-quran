import 'dart:typed_data';
import 'package:drift/drift.dart';
import '../local/db/app_database.dart';
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
  final AppDatabase _db;
  final EmbeddingService _embeddingService;

  static const int hadithOffset = 100000;
  static const int tafsirOffset = 200000;

  RagRepository(this._db, this._embeddingService);

  /// Checks if the vector index is populated. If empty, generates embeddings and indexes all content.
  Future<void> populateVectorIndex() async {
    final countResult = await _db.customSelect('SELECT count(*) as count FROM vec_knowledge_base').getSingle();
    final count = countResult.read<int>('count');

    if (count > 0) return; // Already populated

    // Fetch all verses, hadiths, and tafsirs
    final verses = await _db.select(_db.verses).get();
    final hadiths = await _db.select(_db.hadiths).get();
    final tafsirs = await _db.select(_db.tafsirs).get();

    for (final verse in verses) {
      final embedding = await _embeddingService.getEmbedding(verse.englishText);
      await _insertVector(verse.id, embedding);
    }

    for (final hadith in hadiths) {
      final embedding = await _embeddingService.getEmbedding(hadith.englishText);
      await _insertVector(hadithOffset + hadith.id, embedding);
    }

    for (final tafsir in tafsirs) {
      final embedding = await _embeddingService.getEmbedding(tafsir.contentEnglish);
      await _insertVector(tafsirOffset + tafsir.id, embedding);
    }
  }

  Future<void> _insertVector(int rowid, List<double> embedding) async {
    final float32list = Float32List.fromList(embedding);
    final blob = float32list.buffer.asUint8List();

    await _db.customStatement(
      'INSERT OR REPLACE INTO vec_knowledge_base(rowid, embedding) VALUES (?, ?)',
      [rowid, blob],
    );
  }

  /// Performs vector similarity search. Returns top k matches.
  Future<List<RagSearchResult>> search(String query, {int limit = 5}) async {
    // Ensure index is populated
    await populateVectorIndex();

    final queryVector = await _embeddingService.getEmbedding(query);
    final float32list = Float32List.fromList(queryVector);
    final queryBlob = float32list.buffer.asUint8List();

    final searchResults = <RagSearchResult>[];

    if (_db.hasVectorExtension) {
      final results = await _db.customSelect(
        '''
        SELECT rowid, distance 
        FROM vec_knowledge_base 
        WHERE embedding MATCH ? 
        AND k = ?
        ''',
        variables: [
          Variable.withBlob(queryBlob),
          Variable.withInt(limit),
        ],
      ).get();

      for (final row in results) {
        final rowid = row.read<int>('rowid');
        final distance = row.read<double>('distance');
        final score = 1.0 - distance;

        final match = await _buildSearchResult(rowid, score);
        if (match.verse != null || match.hadith != null || match.tafsir != null) {
          searchResults.add(match);
        }
      }
    } else {
      // Fallback search in Dart (for tests/environments without sqlite-vec loaded)
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

      // Sort by score descending
      scoredRows.sort((a, b) => b.score.compareTo(a.score));

      // Limit results
      final topRows = scoredRows.take(limit);

      for (final row in topRows) {
        final match = await _buildSearchResult(row.rowid, row.score);
        if (match.verse != null || match.hadith != null || match.tafsir != null) {
          searchResults.add(match);
        }
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
