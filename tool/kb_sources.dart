/// Real, verified source endpoints — see
/// docs/superpowers/specs/2026-07-05-knowledge-base-v1-design.md for the
/// verification trail. Do not add or guess new endpoints here without the
/// same live verification.
library;

const quranBaseUrl = 'https://api.alquran.cloud/v1/quran';
const quranArabicEdition = 'quran-uthmani';
const quranEnglishEdition = 'en.sahih';
const quranBanglaEdition = 'bn.bengali';

const hadithBaseUrl = 'https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions';
const hadithBooks = {
  'Sahih al-Bukhari': {'ar': 'ara-bukhari', 'en': 'eng-bukhari', 'bn': 'ben-bukhari'},
  'Sahih Muslim': {'ar': 'ara-muslim', 'en': 'eng-muslim', 'bn': 'ben-muslim'},
};

const tafsirBaseUrl = 'https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir';
const tafsirEnglishSlug = 'en-tafisr-ibn-kathir';
const tafsirBanglaSlug = 'bn-tafseer-ibn-e-kaseer';

class QuranRow {
  final int surahNumber;
  final int ayahNumber;
  final int juzNumber;
  final String text;
  QuranRow({required this.surahNumber, required this.ayahNumber, required this.juzNumber, required this.text});
}

/// Flattens an alquran.cloud `/v1/quran/{edition}` response into one row
/// per ayah. [json] is the decoded top-level response map.
List<QuranRow> parseQuranEdition(Map<String, dynamic> json) {
  final surahs = (json['data'] as Map<String, dynamic>)['surahs'] as List<dynamic>;
  final rows = <QuranRow>[];
  for (final surah in surahs) {
    final surahNumber = surah['number'] as int;
    final ayahs = surah['ayahs'] as List<dynamic>;
    for (final ayah in ayahs) {
      rows.add(QuranRow(
        surahNumber: surahNumber,
        ayahNumber: ayah['numberInSurah'] as int,
        juzNumber: ayah['juz'] as int,
        text: ayah['text'] as String,
      ));
    }
  }
  return rows;
}

class HadithRow {
  final String hadithNumber;
  final String chapterTitle;
  final String text;
  HadithRow({required this.hadithNumber, required this.chapterTitle, required this.text});
}

/// Parses a `fawazahmed0/hadith-api` edition JSON (e.g. `eng-bukhari.json`)
/// into flat rows, resolving each hadith's chapter title from
/// `metadata.sections` via its `reference.book` number.
List<HadithRow> parseHadithEdition(Map<String, dynamic> json) {
  final sections = (json['metadata'] as Map<String, dynamic>)['sections'] as Map<String, dynamic>;
  final hadiths = json['hadiths'] as List<dynamic>;
  final rows = <HadithRow>[];
  for (final h in hadiths) {
    final reference = h['reference'] as Map<String, dynamic>;
    final bookNumber = reference['book'].toString();
    rows.add(HadithRow(
      hadithNumber: h['hadithnumber'].toString(),
      chapterTitle: (sections[bookNumber] as String?) ?? '',
      text: h['text'] as String,
    ));
  }
  return rows;
}

class TafsirRow {
  final int ayahNumber;
  final String text;
  TafsirRow({required this.ayahNumber, required this.text});
}

/// Parses a `spa5k/tafsir_api` per-surah response (a JSON array) into rows.
/// Grouped-ayah commentary appears as duplicated text across consecutive
/// entries in the source itself — preserved as-is, not deduplicated.
List<TafsirRow> parseTafsirSurah(List<dynamic> json) {
  return json
      .map((entry) => TafsirRow(
            ayahNumber: entry['ayah'] as int,
            text: entry['text'] as String,
          ))
      .toList();
}
