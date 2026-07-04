import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:learn_quran/data/local/db/app_database.dart';
import 'package:learn_quran/data/repositories/user_repository.dart';
import 'package:learn_quran/core/services/llm_service.dart';

void main() {
  late AppDatabase db;
  late UserRepository userRepo;
  late LlmService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    userRepo = UserRepository(db);
    service = LlmService(userRepo);
  });

  tearDown(() async {
    await db.close();
  });

  group('LlmService Tests', () {
    test('getSelectedModelPath returns model based on RAM default', () async {
      final path = await service.getSelectedModelPath();
      final meminfo = File('/proc/meminfo');
      double ramGb = 4.0;
      if (meminfo.existsSync()) {
        final lines = meminfo.readAsLinesSync();
        for (final line in lines) {
          if (line.startsWith('MemTotal:')) {
            final match = RegExp(r'\d+').firstMatch(line);
            if (match != null) {
              final totalKb = int.parse(match.group(0)!);
              ramGb = totalKb / (1024 * 1024);
            }
          }
        }
      }
      if (ramGb >= 6.0) {
        expect(path, 'assets/models/gemma_4_e4b.gguf');
      } else {
        expect(path, 'assets/models/gemma_4_e2b.gguf');
      }
    });

    test('getSelectedModelPath respects user settings selection', () async {
      await userRepo.setEngagementValue('selected_llm_model', 'e4b');
      final path = await service.getSelectedModelPath();
      expect(path, 'assets/models/gemma_4_e4b.gguf');

      await userRepo.setEngagementValue('selected_llm_model', 'e2b');
      final path2 = await service.getSelectedModelPath();
      expect(path2, 'assets/models/gemma_4_e2b.gguf');
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
