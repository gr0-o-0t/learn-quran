import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:learn_quran/data/local/db/app_database.dart';
import 'package:learn_quran/data/repositories/user_repository.dart';
import 'package:learn_quran/core/services/llm_service.dart';
import 'package:learn_quran/core/services/model_download_service.dart';
import 'package:learn_quran/core/models/model_catalog.dart';

/// Creates a sparse file of exactly [model.sizeBytes] length, without
/// writing real content — real Gemma 4 sizes are multi-gigabyte, so
/// actually allocating that much memory/disk per test would be absurd.
/// `File.truncate` creates a sparse file on this dev machine's filesystem.
Future<void> _createFakeDownloadedFile(Directory dir, ModelInfo model) async {
  final raf = await File('${dir.path}/${model.filename}').open(mode: FileMode.write);
  await raf.truncate(model.sizeBytes);
  await raf.close();
}

void main() {
  late AppDatabase db;
  late UserRepository userRepo;
  late Directory tempModelsDir;
  late ModelDownloadService downloadService;
  late LlmService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    userRepo = UserRepository(db);
    tempModelsDir = Directory.systemTemp.createTempSync('llm_service_test_');
    downloadService = ModelDownloadService.forTesting(modelsDir: tempModelsDir);
    service = LlmService(userRepo, downloadService);
  });

  tearDown(() async {
    await db.close();
    if (await tempModelsDir.exists()) {
      await tempModelsDir.delete(recursive: true);
    }
  });

  group('LlmService Tests', () {
    test('getSelectedModelPath returns null when nothing is downloaded', () async {
      final path = await service.getSelectedModelPath();
      expect(path, isNull);
    });

    test('getSelectedModelPath returns the local file once the recommended model is downloaded', () async {
      final recommended = recommendedModelFor(service.detectDeviceRamGb());
      await _createFakeDownloadedFile(tempModelsDir, recommended);

      final path = await service.getSelectedModelPath();
      expect(path, '${tempModelsDir.path}/${recommended.filename}');
    });

    test("getSelectedModelPath respects the user's selected_llm_model over the RAM default", () async {
      await userRepo.setEngagementValue('selected_llm_model', 'e4b');
      final e4b = modelById('e4b');
      await _createFakeDownloadedFile(tempModelsDir, e4b);

      final path = await service.getSelectedModelPath();
      expect(path, '${tempModelsDir.path}/${e4b.filename}');
    });

    test('getSelectedModelPath returns null if the selected model is only partially downloaded', () async {
      await userRepo.setEngagementValue('selected_llm_model', 'e2b');
      final e2b = modelById('e2b');
      final path = '${tempModelsDir.path}/${e2b.filename}';
      final raf = await File(path).open(mode: FileMode.write);
      await raf.truncate(e2b.sizeBytes - 1024); // one KB short of complete
      await raf.close();

      final result = await service.getSelectedModelPath();
      expect(result, isNull);
    });

    test('generateResponseStream generates gentle responses', () async {
      final stream = service.generateResponseStream('What does the Quran say about patience?', '');
      final chunks = await stream.toList();
      final fullResponse = chunks.join();

      expect(fullResponse, contains('As-Salamu Alaykum'));
      expect(fullResponse, contains('patience'));
      expect(fullResponse, contains('Al-Baqarah'));
    });

    test('generateResponseStream uses RAG context when provided', () async {
      final stream = service.generateResponseStream('Tell me about the Prophet', 'Hadith states that honesty is salvation.');
      final chunks = await stream.toList();
      final fullResponse = chunks.join();

      expect(fullResponse, contains('As-Salamu Alaykum'));
      expect(fullResponse, contains('honesty is salvation'));
    });
  });
}
