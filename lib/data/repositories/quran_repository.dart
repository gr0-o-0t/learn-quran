import 'package:drift/drift.dart';
import '../local/db/knowledge_base_database.dart';

class QuranRepository {
  final KnowledgeBaseDatabase _db;

  QuranRepository(this._db);

  Future<List<Verse>> getAllVerses() {
    return _db.select(_db.verses).get();
  }

  /// True if the knowledge base has any real content — false for a fresh,
  /// empty (schema-only) database (nothing downloaded yet).
  Future<bool> hasContent() async {
    final result = await _db.customSelect('SELECT count(*) as c FROM verses').getSingle();
    return result.read<int>('c') > 0;
  }

  Future<List<Verse>> getVersesBySurah(int surahNumber) {
    return (_db.select(_db.verses)
          ..where((t) => t.surahNumber.equals(surahNumber))
          ..orderBy([(t) => OrderingTerm.asc(t.ayahNumber)]))
        .get();
  }

  Future<Verse?> getVerse(int surahNumber, int ayahNumber) {
    return (_db.select(_db.verses)
          ..where((t) =>
              t.surahNumber.equals(surahNumber) &
              t.ayahNumber.equals(ayahNumber)))
        .getSingleOrNull();
  }

  Future<List<Verse>> getVersesByJuz(int juzNumber) {
    return (_db.select(_db.verses)
          ..where((t) => t.juzNumber.equals(juzNumber)))
        .get();
  }

  Future<List<Hadith>> getHadithsByBook(String bookName) {
    return (_db.select(_db.hadiths)
          ..where((t) => t.bookName.equals(bookName)))
        .get();
  }

  Future<List<Hadith>> searchHadiths(String query) {
    return (_db.select(_db.hadiths)
          ..where((t) => t.englishText.like('%$query%')))
        .get();
  }

  Future<List<Tafsir>> getTafsirForVerse(int surahNumber, int ayahNumber) {
    return (_db.select(_db.tafsirs)
          ..where((t) =>
              t.surahNumber.equals(surahNumber) &
              t.ayahNumber.equals(ayahNumber)))
        .get();
  }
}
