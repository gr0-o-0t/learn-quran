import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:args/args.dart';
import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:learn_quran/data/local/db/knowledge_base_database.dart';
import 'package:learn_quran/core/services/embedding_service.dart';
import 'kb_sources.dart' as kbsrc;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('output', abbr: 'o', mandatory: true, help: 'Path to write kb.db to.')
    ..addOption('version', mandatory: true, help: 'Knowledge base version, e.g. 1.0.0');
  final args = parser.parse(arguments);
  final outputPath = args['output'] as String;
  final version = args['version'] as String;

  final outputFile = File(outputPath);
  if (await outputFile.exists()) {
    await outputFile.delete();
  }

  final db = KnowledgeBaseDatabase.fromFile(outputPath);
  final client = http.Client();
  final embeddingService = EmbeddingService();

  try {
    stdout.writeln('Fetching Quran (Arabic/English/Bangla)...');
    await _fetchAndInsertQuran(db, client);

    stdout.writeln('Fetching Hadith (Sahih al-Bukhari + Sahih Muslim)...');
    var hadithId = 1;
    for (final entry in kbsrc.hadithBooks.entries) {
      hadithId = await _fetchAndInsertHadithBook(db, client, entry.key, entry.value, hadithId);
    }

    stdout.writeln('Fetching Tafsir Ibn Kathir (English/Bangla)...');
    await _fetchAndInsertTafsir(db, client);

    stdout.writeln('Embedding English text (this takes a while for the full corpus)...');
    await _embedAndIndex(db, embeddingService);

    await db.into(db.kbMeta).insert(KbMetaCompanion.insert(key: 'version', value: version));
    await db.into(db.kbMeta).insert(
          KbMetaCompanion.insert(key: 'built_at', value: DateTime.now().toIso8601String()),
        );
    await db.into(db.kbMeta).insert(
          KbMetaCompanion.insert(key: 'embedding_model', value: 'BAAI/bge-small-en-v1.5'),
        );

    stdout.writeln('Done: $outputPath');
  } finally {
    client.close();
    embeddingService.dispose();
    await db.close();
  }
}

Future<void> _fetchAndInsertQuran(KnowledgeBaseDatabase db, http.Client client) async {
  final arabic = kbsrc.parseQuranEdition(
    jsonDecode((await client.get(Uri.parse('${kbsrc.quranBaseUrl}/${kbsrc.quranArabicEdition}'))).body),
  );
  final english = kbsrc.parseQuranEdition(
    jsonDecode((await client.get(Uri.parse('${kbsrc.quranBaseUrl}/${kbsrc.quranEnglishEdition}'))).body),
  );
  final bangla = kbsrc.parseQuranEdition(
    jsonDecode((await client.get(Uri.parse('${kbsrc.quranBaseUrl}/${kbsrc.quranBanglaEdition}'))).body),
  );

  var id = 1;
  for (var i = 0; i < arabic.length; i++) {
    await db.into(db.verses).insert(VersesCompanion.insert(
          id: Value(id),
          surahNumber: arabic[i].surahNumber,
          ayahNumber: arabic[i].ayahNumber,
          juzNumber: arabic[i].juzNumber,
          arabicText: arabic[i].text,
          englishText: english[i].text,
          banglaText: bangla[i].text,
        ));
    id++;
  }
}

Future<int> _fetchAndInsertHadithBook(
  KnowledgeBaseDatabase db,
  http.Client client,
  String bookName,
  Map<String, String> editionsByLang,
  int startId,
) async {
  final arabic = kbsrc.parseHadithEdition(
    jsonDecode((await client.get(Uri.parse('${kbsrc.hadithBaseUrl}/${editionsByLang['ar']}.json'))).body),
  );
  final english = kbsrc.parseHadithEdition(
    jsonDecode((await client.get(Uri.parse('${kbsrc.hadithBaseUrl}/${editionsByLang['en']}.json'))).body),
  );
  final bangla = kbsrc.parseHadithEdition(
    jsonDecode((await client.get(Uri.parse('${kbsrc.hadithBaseUrl}/${editionsByLang['bn']}.json'))).body),
  );

  var id = startId;
  for (var i = 0; i < english.length; i++) {
    await db.into(db.hadiths).insert(HadithsCompanion.insert(
          id: Value(id),
          bookName: bookName,
          hadithNumber: english[i].hadithNumber,
          chapterTitle: english[i].chapterTitle,
          arabicText: i < arabic.length ? arabic[i].text : '',
          englishText: english[i].text,
          banglaText: i < bangla.length ? bangla[i].text : '',
        ));
    id++;
  }
  return id;
}

Future<void> _fetchAndInsertTafsir(KnowledgeBaseDatabase db, http.Client client) async {
  var id = 1;
  for (var surahNumber = 1; surahNumber <= 114; surahNumber++) {
    final englishResponse = await client.get(Uri.parse('${kbsrc.tafsirBaseUrl}/${kbsrc.tafsirEnglishSlug}/$surahNumber.json'));
    final banglaResponse = await client.get(Uri.parse('${kbsrc.tafsirBaseUrl}/${kbsrc.tafsirBanglaSlug}/$surahNumber.json'));
    final english = kbsrc.parseTafsirSurah(jsonDecode(englishResponse.body));
    final bangla = kbsrc.parseTafsirSurah(jsonDecode(banglaResponse.body));

    for (var i = 0; i < english.length; i++) {
      await db.into(db.tafsirs).insert(TafsirsCompanion.insert(
            id: Value(id),
            surahNumber: surahNumber,
            ayahNumber: english[i].ayahNumber,
            author: 'Ibn Kathir',
            contentEnglish: english[i].text,
            contentBangla: i < bangla.length ? bangla[i].text : '',
          ));
      id++;
    }
  }
}

/// Embeds every row's English text and writes vec_knowledge_base, using the
/// same hadithOffset/tafsirOffset rowid scheme RagRepository.search() reads.
Future<void> _embedAndIndex(KnowledgeBaseDatabase db, EmbeddingService embeddingService) async {
  const hadithOffset = 100000;
  const tafsirOffset = 200000;

  final verses = await db.select(db.verses).get();
  for (final verse in verses) {
    final embedding = await embeddingService.getEmbedding(verse.englishText);
    await _insertVector(db, verse.id, embedding);
  }

  final hadiths = await db.select(db.hadiths).get();
  for (final hadith in hadiths) {
    final embedding = await embeddingService.getEmbedding(hadith.englishText);
    await _insertVector(db, hadithOffset + hadith.id, embedding);
  }

  final tafsirs = await db.select(db.tafsirs).get();
  for (final tafsir in tafsirs) {
    final embedding = await embeddingService.getEmbedding(tafsir.contentEnglish);
    await _insertVector(db, tafsirOffset + tafsir.id, embedding);
  }
}

Future<void> _insertVector(KnowledgeBaseDatabase db, int rowid, List<double> embedding) async {
  final float32list = Float32List.fromList(embedding);
  final blob = float32list.buffer.asUint8List();
  await db.customStatement(
    'INSERT OR REPLACE INTO vec_knowledge_base(rowid, embedding) VALUES (?, ?)',
    [rowid, blob],
  );
}
