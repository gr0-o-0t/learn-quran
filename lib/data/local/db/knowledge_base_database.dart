import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'knowledge_base_database.g.dart';

class Verses extends Table {
  IntColumn get id => integer()();
  IntColumn get surahNumber => integer()();
  IntColumn get ayahNumber => integer()();
  IntColumn get juzNumber => integer()();
  TextColumn get arabicText => text()();
  TextColumn get englishText => text()();
  TextColumn get banglaText => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Hadiths extends Table {
  IntColumn get id => integer()();
  TextColumn get bookName => text()();
  TextColumn get hadithNumber => text()();
  TextColumn get chapterTitle => text()();
  TextColumn get arabicText => text()();
  TextColumn get englishText => text()();
  TextColumn get banglaText => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tafsirs extends Table {
  IntColumn get id => integer()();
  IntColumn get surahNumber => integer()();
  IntColumn get ayahNumber => integer()();
  TextColumn get author => text()();
  TextColumn get contentEnglish => text()();
  TextColumn get contentBangla => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class KbMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class TafsirChunks extends Table {
  IntColumn get id => integer()();
  IntColumn get tafsirId => integer()();
  IntColumn get surahNumber => integer()();
  IntColumn get ayahNumber => integer()();
  TextColumn get author => text()();
  IntColumn get chunkIndex => integer()();
  TextColumn get contentEnglish => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Bm25Postings extends Table {
  TextColumn get term => text()();
  IntColumn get docId => integer()();
  IntColumn get termFrequency => integer()();
}

class Bm25DocStats extends Table {
  IntColumn get docId => integer()();
  IntColumn get docLength => integer()();

  @override
  Set<Column> get primaryKey => {docId};
}

@DriftDatabase(tables: [Verses, Hadiths, Tafsirs, KbMeta, TafsirChunks, Bm25Postings, Bm25DocStats])
class KnowledgeBaseDatabase extends _$KnowledgeBaseDatabase {
  KnowledgeBaseDatabase.forTesting(super.executor);

  /// Opens (or creates) the database at an explicit file [path] — used both
  /// by the app (a writable copy of the bundled/downloaded asset) and by
  /// `tool/build_kb.dart` (building a fresh file from scratch).
  KnowledgeBaseDatabase.fromFile(String path) : super(NativeDatabase.createInBackground(File(path)));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createVectorTable();
          await _createBm25TermIndex();
        },
        beforeOpen: (details) async {
          await _createVectorTable();
          await _createBm25TermIndex();
        },
      );

  Future<void> _createVectorTable() async {
    // Always the plain fallback shape — see Rules.md / design doc: the
    // sqlite-vec native extension does not currently load in this
    // environment, so this ships in the format the Dart-side fallback
    // search (RagRepository.search) actually reads.
    await customStatement('''
      CREATE TABLE IF NOT EXISTS vec_knowledge_base (
        rowid INTEGER PRIMARY KEY,
        embedding BLOB
      );
    ''');
  }

  Future<void> _createBm25TermIndex() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_bm25_postings_term ON bm25_postings (term);',
    );
  }
}
