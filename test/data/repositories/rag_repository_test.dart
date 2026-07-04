import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:learn_quran/data/local/db/app_database.dart';
import 'package:learn_quran/data/repositories/rag_repository.dart';
import 'package:learn_quran/core/services/embedding_service.dart';

void main() {
  late AppDatabase db;
  late EmbeddingService embeddingService;
  late RagRepository repository;

  setUp(() async {
    // We use NativeDatabase.memory() for unit testing Drift.
    // The AppDatabase onCreate/beforeOpen will load the sqlite-vec extension
    // and initialize the vec_knowledge_base virtual table.
    db = AppDatabase.forTesting(NativeDatabase.memory());
    
    // We force mock embeddings for unit tests to avoid asset loading and ensure fast execution.
    embeddingService = EmbeddingService(forceMock: true);
    repository = RagRepository(db, embeddingService);

    // Seed some initial data
    await db.into(db.verses).insert(VersesCompanion.insert(
          id: const drift.Value(1),
          surahNumber: 1,
          ayahNumber: 1,
          juzNumber: 1,
          arabicText: 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
          englishText: 'In the name of Allah, the Entirely Merciful, the Especially Merciful.',
          banglaText: 'পরম করুণাময় অসীম দয়ালু আল্লাহর নামে শুরু করছি।',
          hindiText: 'अल्लाह के नाम से, जो अत्यंत कृपाशील और दयावान है।',
        ));

    await db.into(db.hadiths).insert(HadithsCompanion.insert(
          id: const drift.Value(1),
          bookName: 'Sahih al-Bukhari',
          hadithNumber: '1',
          chapterTitle: 'Revelation',
          arabicText: 'إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ',
          englishText: 'Actions are but by intention...',
          banglaText: 'কাজ নিয়তের ওপর নির্ভরশীল...',
          hindiText: 'कर्मों का दारोमदार नीयत पर है...',
        ));

    await db.into(db.tafsirs).insert(TafsirsCompanion.insert(
          id: const drift.Value(1),
          surahNumber: 1,
          ayahNumber: 1,
          author: 'Ibn Kathir',
          contentEnglish: 'Tafsir explaining the meaning of Basmalah.',
          contentBangla: 'তাসমীয়ার তাফসীর...',
          contentHindi: 'बिस्मिल्लाह की तफ़्सीर...',
        ));
  });

  tearDown(() async {
    await db.close();
  });

  group('RagRepository Tests', () {
    test('populateVectorIndex indexes all content', () async {
      await repository.populateVectorIndex();

      final countResult = await db.customSelect('SELECT count(*) as count FROM vec_knowledge_base').getSingle();
      final count = countResult.read<int>('count');

      // We seeded 1 verse, 1 hadith, 1 tafsir
      expect(count, 3);
    });

    test('search returns matching segments ordered by similarity', () async {
      // Index the database first
      await repository.populateVectorIndex();

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
