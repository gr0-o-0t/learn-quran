import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:learn_quran/data/local/db/knowledge_base_database.dart';
import 'package:learn_quran/data/repositories/quran_repository.dart';
import 'package:drift/drift.dart' as drift;

void main() {
  late KnowledgeBaseDatabase db;
  late QuranRepository repository;

  setUp(() async {
    db = KnowledgeBaseDatabase.forTesting(NativeDatabase.memory());
    repository = QuranRepository(db);

    // Seed some test data
    await db.into(db.verses).insert(VersesCompanion.insert(
          id: const drift.Value(1),
          surahNumber: 1,
          ayahNumber: 1,
          juzNumber: 1,
          arabicText: 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
          englishText: 'In the name of Allah, the Entirely Merciful, the Especially Merciful.',
          banglaText: 'পরম করুণাময় অসীম দয়ালু আল্লাহর নামে শুরু করছি।',
        ));

    await db.into(db.verses).insert(VersesCompanion.insert(
          id: const drift.Value(2),
          surahNumber: 1,
          ayahNumber: 2,
          juzNumber: 1,
          arabicText: 'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ',
          englishText: '[All] praise is [due] to Allah, Lord of the worlds -',
          banglaText: 'সব প্রশংসা জগতসমূহের প্রতিপালক আল্লাহর জন্য।',
        ));

    await db.into(db.hadiths).insert(HadithsCompanion.insert(
          id: const drift.Value(1),
          bookName: 'Bukhari',
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
          contentEnglish: 'Tafsir of verse 1...',
          contentBangla: '১ নম্বর আয়াতের তাফসীর...',
        ));
  });

  tearDown(() async {
    await db.close();
  });

  group('QuranRepository Tests', () {
    test('getAllVerses returns all seeded verses', () async {
      final verses = await repository.getAllVerses();
      expect(verses.length, 2);
      expect(verses[0].ayahNumber, 1);
      expect(verses[1].ayahNumber, 2);
    });

    test('getVersesBySurah returns verses of specific surah', () async {
      final verses = await repository.getVersesBySurah(1);
      expect(verses.length, 2);
      expect(verses[0].surahNumber, 1);
    });

    test('getVerse returns specific verse or null', () async {
      final verse = await repository.getVerse(1, 2);
      expect(verse, isNotNull);
      expect(verse!.arabicText, 'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ');

      final nonExistent = await repository.getVerse(1, 3);
      expect(nonExistent, isNull);
    });

    test('getHadithsByBook returns book hadiths', () async {
      final hadiths = await repository.getHadithsByBook('Bukhari');
      expect(hadiths.length, 1);
      expect(hadiths[0].hadithNumber, '1');
    });

    test('searchHadiths returns matching hadiths', () async {
      final results = await repository.searchHadiths('intention');
      expect(results.length, 1);
      expect(results[0].englishText, contains('intention'));

      final emptyResults = await repository.searchHadiths('patience');
      expect(emptyResults, isEmpty);
    });

    test('getTafsirForVerse returns tafsir details', () async {
      final tafsirList = await repository.getTafsirForVerse(1, 1);
      expect(tafsirList.length, 1);
      expect(tafsirList[0].author, 'Ibn Kathir');
    });

    test('hasContent returns true when verses exist', () async {
      expect(await repository.hasContent(), isTrue);
    });
  });

  group('QuranRepository.hasContent on an empty database', () {
    test('returns false for a fresh, schema-only database', () async {
      final emptyDb = KnowledgeBaseDatabase.forTesting(NativeDatabase.memory());
      final emptyRepo = QuranRepository(emptyDb);
      expect(await emptyRepo.hasContent(), isFalse);
      await emptyDb.close();
    });
  });
}
