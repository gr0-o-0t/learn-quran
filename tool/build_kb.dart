import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:args/args.dart';
import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:learn_quran/data/local/db/knowledge_base_database.dart';
import 'package:learn_quran/core/services/embedding_service.dart';
import 'kb_sources.dart' as kbsrc;
import 'package:learn_quran/core/utils/text_chunking.dart';
import 'package:learn_quran/core/utils/bm25_tokenizer.dart';

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

    stdout.writeln('Fetching Tafsir Ibn Kathir (English/Bangla) and chunking long entries...');
    await embeddingService.init();
    await _fetchAndInsertTafsir(db, client, embeddingService);

    stdout.writeln('Embedding English text and building the BM25 index (this takes a while for the full corpus)...');
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
  var skipped = 0;
  for (var i = 0; i < english.length; i++) {
    // A handful of hadith numbers have no English translation in the
    // upstream fawazahmed0/hadith-api source itself (confirmed genuine gap,
    // not a fetch/parse bug). Shipping a blank englishText would be useless
    // for reading and for the RAG index, so skip rather than insert it.
    if (english[i].text.trim().isEmpty) {
      skipped++;
      continue;
    }
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
  if (skipped > 0) {
    stdout.writeln('  $bookName: skipped $skipped/${english.length} hadiths with no English text');
  }
  return id;
}

Future<void> _fetchAndInsertTafsir(
  KnowledgeBaseDatabase db,
  http.Client client,
  EmbeddingService embeddingService,
) async {
  var tafsirId = 1;
  var chunkId = 1;
  var totalChunks = 0;
  var totalEntries = 0;

  for (var surahNumber = 1; surahNumber <= 114; surahNumber++) {
    final englishResponse =
        await client.get(Uri.parse('${kbsrc.tafsirBaseUrl}/${kbsrc.tafsirEnglishSlug}/$surahNumber.json'));
    final banglaResponse =
        await client.get(Uri.parse('${kbsrc.tafsirBaseUrl}/${kbsrc.tafsirBanglaSlug}/$surahNumber.json'));
    final english = kbsrc.parseTafsirSurah(jsonDecode(englishResponse.body));
    final bangla = kbsrc.parseTafsirSurah(jsonDecode(banglaResponse.body));

    for (var i = 0; i < english.length; i++) {
      await db.into(db.tafsirs).insert(TafsirsCompanion.insert(
            id: Value(tafsirId),
            surahNumber: surahNumber,
            ayahNumber: english[i].ayahNumber,
            author: 'Ibn Kathir',
            contentEnglish: english[i].text,
            contentBangla: i < bangla.length ? bangla[i].text : '',
          ));

      final chunks = chunkText(
        english[i].text,
        maxTokens: 200,
        countTokens: embeddingService.countTokensSync,
      );
      totalEntries++;
      totalChunks += chunks.length;
      for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
        await db.into(db.tafsirChunks).insert(TafsirChunksCompanion.insert(
              id: Value(chunkId),
              tafsirId: tafsirId,
              surahNumber: surahNumber,
              ayahNumber: english[i].ayahNumber,
              author: 'Ibn Kathir',
              chunkIndex: chunkIndex,
              contentEnglish: chunks[chunkIndex],
            ));
        chunkId++;
      }

      tafsirId++;
    }
  }

  stdout.writeln('  Tafsir: $totalEntries entries -> $totalChunks chunks '
      '(${totalChunks - totalEntries} entries split into multiple chunks)');
}

/// Embeds every verse/hadith/tafsir-chunk's English text into
/// vec_knowledge_base, and computes the BM25 term-frequency/document-length
/// statistics into bm25_postings/bm25_doc_stats/kb_meta — both using the
/// same hadithOffset/tafsirOffset rowid scheme RagRepository.search() reads.
Future<void> _embedAndIndex(KnowledgeBaseDatabase db, EmbeddingService embeddingService) async {
  const hadithOffset = 100000;
  const tafsirOffset = 200000;

  final docLengths = <int, int>{};
  final termFrequenciesByDoc = <int, Map<String, int>>{};

  Future<void> indexDoc(int docId, String text) async {
    final embedding = await embeddingService.getEmbedding(text);
    await _insertVector(db, docId, embedding);

    final tokens = tokenizeForBm25(text);
    docLengths[docId] = tokens.length;
    final freq = <String, int>{};
    for (final token in tokens) {
      freq[token] = (freq[token] ?? 0) + 1;
    }
    termFrequenciesByDoc[docId] = freq;
  }

  final verses = await db.select(db.verses).get();
  for (final verse in verses) {
    await indexDoc(verse.id, verse.englishText);
  }

  final hadiths = await db.select(db.hadiths).get();
  for (final hadith in hadiths) {
    await indexDoc(hadithOffset + hadith.id, hadith.englishText);
  }

  final tafsirChunks = await db.select(db.tafsirChunks).get();
  for (final chunk in tafsirChunks) {
    await indexDoc(tafsirOffset + chunk.id, chunk.contentEnglish);
  }

  stdout.writeln('Building BM25 index (${termFrequenciesByDoc.length} documents)...');
  await db.batch((batch) {
    for (final entry in termFrequenciesByDoc.entries) {
      final docId = entry.key;
      for (final termEntry in entry.value.entries) {
        batch.insert(
          db.bm25Postings,
          Bm25PostingsCompanion.insert(term: termEntry.key, docId: docId, termFrequency: termEntry.value),
        );
      }
      // docId is Bm25DocStats's primary key, so Drift generates it as an
      // optional Value<int> in .insert(...) — must be wrapped, unlike the
      // plain-int docId on Bm25Postings above (no primary key there).
      batch.insert(
        db.bm25DocStats,
        Bm25DocStatsCompanion.insert(docId: Value(docId), docLength: docLengths[docId]!),
      );
    }
  });

  final avgDocLength = docLengths.values.isEmpty
      ? 0.0
      : docLengths.values.reduce((a, b) => a + b) / docLengths.values.length;
  await db.into(db.kbMeta).insert(
        KbMetaCompanion.insert(key: 'bm25_doc_count', value: termFrequenciesByDoc.length.toString()),
      );
  await db.into(db.kbMeta).insert(
        KbMetaCompanion.insert(key: 'bm25_avg_doc_length', value: avgDocLength.toString()),
      );
}

Future<void> _insertVector(KnowledgeBaseDatabase db, int rowid, List<double> embedding) async {
  final float32list = Float32List.fromList(embedding);
  final blob = float32list.buffer.asUint8List();
  await db.customStatement(
    'INSERT OR REPLACE INTO vec_knowledge_base(rowid, embedding) VALUES (?, ?)',
    [rowid, blob],
  );
}
