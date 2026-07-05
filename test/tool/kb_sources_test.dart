import 'package:flutter_test/flutter_test.dart';
import '../../tool/kb_sources.dart' as kbsrc;

void main() {
  group('parseQuranEdition', () {
    test('flattens surahs/ayahs into flat verse rows', () {
      final fixture = {
        'data': {
          'surahs': [
            {
              'number': 1,
              'ayahs': [
                {'number': 1, 'numberInSurah': 1, 'juz': 1, 'text': 'بِسْمِ اللَّهِ'},
                {'number': 2, 'numberInSurah': 2, 'juz': 1, 'text': 'الْحَمْدُ لِلَّهِ'},
              ],
            },
          ],
        },
      };
      final rows = kbsrc.parseQuranEdition(fixture);
      expect(rows.length, 2);
      expect(rows[0].surahNumber, 1);
      expect(rows[0].ayahNumber, 1);
      expect(rows[0].juzNumber, 1);
      expect(rows[0].text, 'بِسْمِ اللَّهِ');
      expect(rows[1].ayahNumber, 2);
    });
  });

  group('parseHadithEdition', () {
    test('maps hadith rows and resolves chapter titles from metadata.sections', () {
      final fixture = {
        'metadata': {
          'sections': {'1': 'Revelation', '2': 'Belief'},
        },
        'hadiths': [
          {
            'hadithnumber': 1,
            'text': 'Actions are judged by intentions',
            'reference': {'book': 1, 'hadith': 1},
          },
          {
            'hadithnumber': 2,
            'text': 'Something about belief',
            'reference': {'book': 2, 'hadith': 1},
          },
        ],
      };
      final rows = kbsrc.parseHadithEdition(fixture);
      expect(rows.length, 2);
      expect(rows[0].hadithNumber, '1');
      expect(rows[0].chapterTitle, 'Revelation');
      expect(rows[0].text, 'Actions are judged by intentions');
      expect(rows[1].chapterTitle, 'Belief');
    });
  });

  group('parseTafsirSurah', () {
    test('maps one entry per ayah, preserving duplicated grouped-ayah text as-is', () {
      final fixture = [
        {'surah': 1, 'ayah': 6, 'text': 'shared commentary'},
        {'surah': 1, 'ayah': 7, 'text': 'shared commentary'},
      ];
      final rows = kbsrc.parseTafsirSurah(fixture);
      expect(rows.length, 2);
      expect(rows[0].ayahNumber, 6);
      expect(rows[1].ayahNumber, 7);
      expect(rows[0].text, rows[1].text);
    });
  });
}
