import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:learn_quran/data/local/db/knowledge_base_database.dart';

void main() {
  late Directory tempDir;
  late String kbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kb_safe_open_test');
    kbPath = p.join(tempDir.path, 'kb.db');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('recovers by replacing a stale schema-v1 kb.db with a fresh v2 database', () async {
    // Simulate a kb.db left over from before the TafsirChunks/Bm25Postings/
    // Bm25DocStats tables existed: a real sqlite file whose stored
    // `user_version` is 1, while KnowledgeBaseDatabase now declares
    // schemaVersion 2 with no onUpgrade path — opening it for real query
    // access must trigger Drift's default (throwing) upgrade strategy.
    //
    // Using package:sqlite3 directly (already a transitive dependency via
    // drift, and a direct dependency of this app) rather than drift's own
    // NativeDatabase/QueryExecutorUser API: it lets us stamp user_version on
    // a plain sqlite file with zero drift machinery involved, which keeps
    // this fixture unambiguously "just a real sqlite file", independent of
    // whatever drift's own opening lifecycle does.
    final legacyDb = sqlite3.open(kbPath);
    legacyDb.execute('PRAGMA user_version = 1;');
    legacyDb.close();

    final recovered = await openKnowledgeBaseDatabaseSafely(kbPath);
    addTearDown(recovered.close);

    // The recovered database is a working, fresh v2 schema: querying a
    // table that only exists in v2 must succeed (not throw), and be empty.
    final chunks = await recovered.select(recovered.tafsirChunks).get();
    expect(chunks, isEmpty);
    final postings = await recovered.select(recovered.bm25Postings).get();
    expect(postings, isEmpty);
  });

  test('recovers by replacing a corrupt kb.db file with a fresh v2 database', () async {
    await File(kbPath).writeAsBytes([1, 2, 3, 4, 5]); // not a valid sqlite file at all

    final recovered = await openKnowledgeBaseDatabaseSafely(kbPath);
    addTearDown(recovered.close);

    final chunks = await recovered.select(recovered.tafsirChunks).get();
    expect(chunks, isEmpty);
  });
}
