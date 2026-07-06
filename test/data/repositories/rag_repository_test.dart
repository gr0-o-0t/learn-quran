import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:learn_quran/data/local/db/knowledge_base_database.dart';
import 'package:learn_quran/data/repositories/rag_repository.dart';
import 'package:learn_quran/core/services/embedding_service.dart';

/// Mirrors what the offline `tool/build_kb.dart` writes into
/// `vec_knowledge_base` at build time — embeddings are never generated
/// on-device anymore (see RagRepository.search).
Future<void> _insertVector(KnowledgeBaseDatabase db, int rowid, List<double> embedding) async {
  final float32list = Float32List.fromList(embedding);
  final blob = float32list.buffer.asUint8List();
  await db.customStatement(
    'INSERT OR REPLACE INTO vec_knowledge_base(rowid, embedding) VALUES (?, ?)',
    [rowid, blob],
  );
}

void main() {
  late KnowledgeBaseDatabase db;
  late EmbeddingService embeddingService;
  late RagRepository repository;

  setUp(() async {
    db = KnowledgeBaseDatabase.forTesting(NativeDatabase.memory());
    embeddingService = EmbeddingService(forceMock: true);
    repository = RagRepository(db, embeddingService);

    await db.into(db.verses).insert(VersesCompanion.insert(
          id: const drift.Value(1),
          surahNumber: 1,
          ayahNumber: 1,
          juzNumber: 1,
          arabicText: 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
          englishText: 'In the name of Allah, the Entirely Merciful, the Especially Merciful.',
          banglaText: 'পরম করুণাময় অসীম দয়ালু আল্লাহর নামে শুরু করছি।',
        ));

    await db.into(db.hadiths).insert(HadithsCompanion.insert(
          id: const drift.Value(1),
          bookName: 'Sahih al-Bukhari',
          hadithNumber: '1',
          chapterTitle: 'Revelation',
          arabicText: 'إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ',
          englishText: 'Actions are but by intention...',
          banglaText: 'কাজ নিয়তের ওপর নির্ভরশীল...',
        ));

    await db.into(db.tafsirChunks).insert(TafsirChunksCompanion.insert(
          id: const drift.Value(1),
          tafsirId: 1,
          surahNumber: 1,
          ayahNumber: 1,
          author: 'Ibn Kathir',
          chunkIndex: 0,
          contentEnglish: 'Tafsir explaining the meaning of Basmalah.',
        ));

    await _insertVector(
      db,
      1,
      await embeddingService.getEmbedding('In the name of Allah, the Entirely Merciful, the Especially Merciful.'),
    );
    await _insertVector(
      db,
      RagRepository.hadithOffset + 1,
      await embeddingService.getEmbedding('Actions are but by intention...'),
    );
    await _insertVector(
      db,
      RagRepository.tafsirOffset + 1,
      await embeddingService.getEmbedding('Tafsir explaining the meaning of Basmalah.'),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('RagRepository hybrid search', () {
    test('search returns matching segments ordered by similarity', () async {
      final results = await repository.search('name of Allah', limit: 2);

      expect(results, isNotEmpty);
      expect(results.length, lessThanOrEqualTo(2));

      for (final match in results) {
        if (match.type == RagSourceType.verse) {
          expect(match.verse, isNotNull);
          expect(match.verse!.englishText, contains('Allah'));
        } else if (match.type == RagSourceType.hadith) {
          expect(match.hadith, isNotNull);
          expect(match.hadith!.englishText, contains('intention'));
        } else if (match.type == RagSourceType.tafsir) {
          expect(match.tafsir, isNotNull);
          expect(match.tafsir!.contentEnglish, contains('Basmalah'));
        }
      }
    });

    test('a document found only via BM25 ranks first for an exact keyword match', () async {
      // Its mock embedding has no special relationship to the query below —
      // only the exact keyword match should be able to surface it reliably.
      await db.into(db.hadiths).insert(HadithsCompanion.insert(
            id: const drift.Value(2),
            bookName: 'Sahih Muslim',
            hadithNumber: '99',
            chapterTitle: 'Zakat',
            arabicText: 'زَكَاة',
            englishText: 'A rare distinctive keyword: xenocryst appears here.',
            banglaText: 'যাকাত',
          ));
      await _insertVector(
        db,
        RagRepository.hadithOffset + 2,
        await embeddingService.getEmbedding('A rare distinctive keyword: xenocryst appears here.'),
      );
      await db.batch((batch) {
        batch.insertAll(db.bm25Postings, [
          Bm25PostingsCompanion.insert(term: 'xenocryst', docId: RagRepository.hadithOffset + 2, termFrequency: 1),
        ]);
        // docId is Bm25DocStats's primary key, so Drift generates it as an
        // optional Value<int> in .insert(...) — must be wrapped, unlike the
        // plain-int docId on Bm25Postings above (no primary key there).
        batch.insertAll(db.bm25DocStats, [
          Bm25DocStatsCompanion.insert(docId: const drift.Value(RagRepository.hadithOffset + 2), docLength: 6),
        ]);
        batch.insertAll(db.kbMeta, [
          KbMetaCompanion.insert(key: 'bm25_doc_count', value: '4'),
          KbMetaCompanion.insert(key: 'bm25_avg_doc_length', value: '6.0'),
        ]);
      });

      final results = await repository.search('xenocryst', limit: 1);

      expect(results, hasLength(1));
      expect(results.first.hadith?.id, 2);
    });
  });

  group('citationFor', () {
    test('formats a verse citation with the real surah name', () {
      final result = RagSearchResult(
        type: RagSourceType.verse,
        score: 1,
        verse: const Verse(
          id: 1,
          surahNumber: 2,
          ayahNumber: 153,
          juzNumber: 2,
          arabicText: 'عربي',
          englishText: 'Seek help through patience.',
          banglaText: 'বাংলা',
        ),
      );
      final citation = citationFor(result);
      expect(citation.title, 'Surah Al-Baqarah 2:153');
      expect(citation.text, 'Seek help through patience.');
    });

    test('formats a hadith citation', () {
      final result = RagSearchResult(
        type: RagSourceType.hadith,
        score: 1,
        hadith: const Hadith(
          id: 1,
          bookName: 'Sahih al-Bukhari',
          hadithNumber: '1',
          chapterTitle: 'Revelation',
          arabicText: 'عربي',
          englishText: 'Actions are but by intention.',
          banglaText: 'বাংলা',
        ),
      );
      final citation = citationFor(result);
      expect(citation.title, 'Sahih al-Bukhari Hadith 1');
      expect(citation.text, 'Actions are but by intention.');
    });

    test('formats a tafsir-chunk citation with the real surah name', () {
      final result = RagSearchResult(
        type: RagSourceType.tafsir,
        score: 1,
        tafsir: const TafsirChunk(
          id: 1,
          tafsirId: 1,
          surahNumber: 1,
          ayahNumber: 1,
          author: 'Ibn Kathir',
          chunkIndex: 0,
          contentEnglish: 'Commentary on the Basmalah.',
        ),
      );
      final citation = citationFor(result);
      expect(citation.title, 'Tafsir Al-Fatiha 1:1');
      expect(citation.text, 'Commentary on the Basmalah.');
    });
  });
}
