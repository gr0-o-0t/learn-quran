import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/services/bm25_index.dart';
import 'package:learn_quran/data/local/db/knowledge_base_database.dart';

void main() {
  late KnowledgeBaseDatabase db;
  late Bm25Index index;

  setUp(() async {
    db = KnowledgeBaseDatabase.forTesting(NativeDatabase.memory());
    index = Bm25Index(db);

    // 3 tiny documents, each 3 tokens long (so length-normalization is a
    // no-op and results are hand-verifiable from tf/idf alone):
    //   doc 1: "patience patience prophet"
    //   doc 2: "prophet prophet prophet"
    //   doc 3: "prayer prayer prayer"
    // docId is Bm25DocStats's primary key, so Drift generates it as an
    // optional Value<int> in .insert(...) — it must be wrapped in
    // const Value(...), not passed as a bare int (Bm25Postings has no
    // primary key column, so its docId stays a plain int there).
    await db.batch((batch) {
      batch.insertAll(db.bm25Postings, [
        Bm25PostingsCompanion.insert(term: 'patience', docId: 1, termFrequency: 2),
        Bm25PostingsCompanion.insert(term: 'prophet', docId: 1, termFrequency: 1),
        Bm25PostingsCompanion.insert(term: 'prophet', docId: 2, termFrequency: 3),
        Bm25PostingsCompanion.insert(term: 'prayer', docId: 3, termFrequency: 3),
      ]);
      batch.insertAll(db.bm25DocStats, [
        Bm25DocStatsCompanion.insert(docId: const Value(1), docLength: 3),
        Bm25DocStatsCompanion.insert(docId: const Value(2), docLength: 3),
        Bm25DocStatsCompanion.insert(docId: const Value(3), docLength: 3),
      ]);
      batch.insertAll(db.kbMeta, [
        KbMetaCompanion.insert(key: 'bm25_doc_count', value: '3'),
        KbMetaCompanion.insert(key: 'bm25_avg_doc_length', value: '3.0'),
      ]);
    });
  });

  tearDown(() async {
    await db.close();
  });

  group('Bm25Index', () {
    test('finds the only document containing a rare term', () async {
      final results = await index.search('patience');
      expect(results.map((e) => e.key).toList(), [1]);
    });

    test('ranks a document with higher term frequency above one with lower', () async {
      final results = await index.search('prophet');
      expect(results.map((e) => e.key).toList(), [2, 1]);
    });

    test('returns an empty list for a term not in the index', () async {
      final results = await index.search('nonexistent');
      expect(results, isEmpty);
    });

    test('returns an empty list when BM25 metadata has not been populated', () async {
      final freshDb = KnowledgeBaseDatabase.forTesting(NativeDatabase.memory());
      final freshIndex = Bm25Index(freshDb);
      final results = await freshIndex.search('patience');
      expect(results, isEmpty);
      await freshDb.close();
    });
  });
}
