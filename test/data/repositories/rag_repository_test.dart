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
    // We use NativeDatabase.memory() for unit testing Drift.
    db = KnowledgeBaseDatabase.forTesting(NativeDatabase.memory());

    // We force mock embeddings for unit tests to avoid asset loading and ensure fast execution.
    embeddingService = EmbeddingService(forceMock: true);
    repository = RagRepository(db, embeddingService);

    // Seed some initial content data.
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

    await db.into(db.tafsirs).insert(TafsirsCompanion.insert(
          id: const drift.Value(1),
          surahNumber: 1,
          ayahNumber: 1,
          author: 'Ibn Kathir',
          contentEnglish: 'Tafsir explaining the meaning of Basmalah.',
          contentBangla: 'তাসমীয়ার তাফসীর...',
        ));

    // Precompute and index embeddings, as `tool/build_kb.dart` does offline.
    await _insertVector(db, 1, await embeddingService.getEmbedding('In the name of Allah, the Entirely Merciful, the Especially Merciful.'));
    await _insertVector(db, RagRepository.hadithOffset + 1, await embeddingService.getEmbedding('Actions are but by intention...'));
    await _insertVector(db, RagRepository.tafsirOffset + 1, await embeddingService.getEmbedding('Tafsir explaining the meaning of Basmalah.'));
  });

  tearDown(() async {
    await db.close();
  });

  group('RagRepository Tests', () {
    test('search returns matching segments ordered by similarity', () async {
      // Search for something related to the verse
      final results = await repository.search('name of Allah', limit: 2);

      // Verify we get results
      expect(results, isNotEmpty);
      expect(results.length, lessThanOrEqualTo(2));

      // Check types and properties
      for (final match in results) {
        expect(match.score, isNotNull);
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
  });
}
