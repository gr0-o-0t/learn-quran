import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/data/local/db/knowledge_base_database.dart';

void main() {
  late KnowledgeBaseDatabase db;

  setUp(() {
    db = KnowledgeBaseDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('creates verses/hadiths/tafsirs/kbMeta/vec_knowledge_base tables with no hindi columns', () async {
    await db.into(db.verses).insert(VersesCompanion.insert(
          id: const Value(1),
          surahNumber: 1,
          ayahNumber: 1,
          juzNumber: 1,
          arabicText: 'بِسْمِ اللَّهِ',
          englishText: 'In the name of Allah',
          banglaText: 'আল্লাহর নামে',
        ));
    final verse = await (db.select(db.verses)..where((t) => t.id.equals(1))).getSingle();
    expect(verse.englishText, 'In the name of Allah');

    await db.into(db.kbMeta).insert(KbMetaCompanion.insert(key: 'version', value: '1.0.0'));
    final meta = await (db.select(db.kbMeta)..where((t) => t.key.equals('version'))).getSingle();
    expect(meta.value, '1.0.0');

    // vec_knowledge_base exists and accepts the plain (rowid, embedding) shape.
    await db.customStatement(
      'INSERT INTO vec_knowledge_base(rowid, embedding) VALUES (?, ?)',
      [1, [1, 2, 3, 4]],
    );
    final vecRow = await db.customSelect('SELECT rowid FROM vec_knowledge_base WHERE rowid = 1').getSingle();
    expect(vecRow.read<int>('rowid'), 1);
  });

  test('hadiths and tafsirs tables have no hindi column (compile-time guarantee)', () async {
    await db.into(db.hadiths).insert(HadithsCompanion.insert(
          id: const Value(1),
          bookName: 'Sahih al-Bukhari',
          hadithNumber: '1',
          chapterTitle: 'Revelation',
          arabicText: 'إنما الأعمال بالنيات',
          englishText: 'Actions are judged by intentions',
          banglaText: 'কাজের ফল নিয়তের উপর নির্ভর করে',
        ));
    await db.into(db.tafsirs).insert(TafsirsCompanion.insert(
          id: const Value(1),
          surahNumber: 1,
          ayahNumber: 1,
          author: 'Ibn Kathir',
          contentEnglish: 'Commentary text',
          contentBangla: 'বাংলা তাফসীর',
        ));
    final hadith = await (db.select(db.hadiths)..where((t) => t.id.equals(1))).getSingle();
    final tafsir = await (db.select(db.tafsirs)..where((t) => t.id.equals(1))).getSingle();
    expect(hadith.bookName, 'Sahih al-Bukhari');
    expect(tafsir.author, 'Ibn Kathir');
  });

  test('creates tafsir_chunks/bm25_postings/bm25_doc_stats tables', () async {
    await db.into(db.tafsirChunks).insert(TafsirChunksCompanion.insert(
          id: const Value(1),
          tafsirId: 1,
          surahNumber: 1,
          ayahNumber: 1,
          author: 'Ibn Kathir',
          chunkIndex: 0,
          contentEnglish: 'First chunk of commentary.',
        ));
    final chunk = await (db.select(db.tafsirChunks)..where((t) => t.id.equals(1))).getSingle();
    expect(chunk.contentEnglish, 'First chunk of commentary.');

    await db.into(db.bm25Terms).insert(
          Bm25TermsCompanion.insert(termId: const Value(1), term: 'patience'),
        );
    await db.into(db.bm25Postings).insert(
          Bm25PostingsCompanion.insert(termId: 1, docId: 1, termFrequency: 2),
        );
    final posting = await (db.select(db.bm25Postings)..where((t) => t.termId.equals(1))).getSingle();
    expect(posting.docId, 1);
    expect(posting.termFrequency, 2);

    await db.into(db.bm25DocStats).insert(
          Bm25DocStatsCompanion.insert(docId: const Value(1), docLength: 42),
        );
    final stats = await (db.select(db.bm25DocStats)..where((t) => t.docId.equals(1))).getSingle();
    expect(stats.docLength, 42);
  });
}
