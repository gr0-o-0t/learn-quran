import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/user_repository.dart';
import '../providers/repository_providers.dart';
import 'llama_ffi.dart';

class LlmService {
  final UserRepository? _userRepo;
  bool _initialized = false;
  bool _useMock = true;
  LlamaFfi? _ffi;

  LlmService([this._userRepo]);

  Future<String> getSelectedModelPath() async {
    if (_userRepo != null) {
      final selectedModel = await _userRepo.getEngagementValue('selected_llm_model');
      if (selectedModel == 'e2b') {
        return 'assets/models/gemma_4_e2b.gguf';
      } else if (selectedModel == 'e4b') {
        return 'assets/models/gemma_4_e4b.gguf';
      }
    }

    final ramGb = _detectDeviceRamGb();
    if (ramGb >= 6.0) {
      return 'assets/models/gemma_4_e4b.gguf';
    } else {
      return 'assets/models/gemma_4_e2b.gguf';
    }
  }

  double _detectDeviceRamGb() {
    try {
      if (Platform.isLinux) {
        final meminfo = File('/proc/meminfo');
        if (meminfo.existsSync()) {
          final lines = meminfo.readAsLinesSync();
          for (final line in lines) {
            if (line.startsWith('MemTotal:')) {
              final match = RegExp(r'\d+').firstMatch(line);
              if (match != null) {
                final totalKb = int.parse(match.group(0)!);
                return totalKb / (1024 * 1024);
              }
            }
          }
        }
      }
    } catch (_) {}
    return 4.0; // Default fallback
  }

  Future<void> init() async {
    if (_initialized) return;

    try {
      final libraryPath = Platform.isLinux
          ? 'libllama.so'
          : Platform.isAndroid
              ? 'libllama.so'
              : 'llama.framework/llama';
      
      // Try to load FFI. In testing environment or devices without dynamic library compiled,
      // this will throw an exception, triggering the mock fallback.
      _ffi = LlamaFfi(libraryPath);
      _useMock = false;
    } catch (_) {
      _useMock = true;
    }

    _initialized = true;
  }

  Stream<String> generateResponseStream(String prompt, String ragContext) async* {
    await init();

    if (_useMock || _ffi == null) {
      final responseText = _generateMockResponse(prompt, ragContext);
      final words = responseText.split(' ');
      for (final word in words) {
        await Future.delayed(const Duration(milliseconds: 50));
        yield '$word ';
      }
      return;
    }

    // In a real application, we would call llama.cpp native inference loop here
    yield "On-Device Inference Mode: Loaded via FFI.";
  }

  String _generateMockResponse(String prompt, String ragContext) {
    final lowercasePrompt = prompt.toLowerCase();

    if (lowercasePrompt.contains('reflection') || lowercasePrompt.contains('story')) {
      return "Title: Finding Calm in Patience\n\n"
             "As-Salamu Alaykum. In the journey of life, we often face moments of doubt and tiredness. "
             "However, every verse you read and every Salat you pray brings you closer to divine light. "
             "Remember, patience is a source of strength, and your consistency is beautiful to the Almighty. "
             "Keep moving forward with a peaceful heart, knowing that with every difficulty comes ease.";
    }

    if (lowercasePrompt.contains('patience') || lowercasePrompt.contains('sabr')) {
      return "As-Salamu Alaykum. Patience (Sabr) is a beautiful virtue in Islam. "
             "Allah says in the Quran, 'Indeed, Allah is with the patient' (Surah Al-Baqarah 2:153). "
             "The Prophet Muhammad (peace be upon him) demonstrated patience throughout his life, "
             "responding to difficulties with calmness and prayers for those who opposed him. "
             "When facing adversity, we are encouraged to remain steadfast, trust in Allah's wisdom, and pray.";
    }

    if (lowercasePrompt.contains('sadness') || lowercasePrompt.contains('grief') || lowercasePrompt.contains('sorrow')) {
      return "As-Salamu Alaykum. It is natural to feel sadness. Even the Prophet Muhammad (peace be upon him) experienced grief, "
             "such as during the Year of Sorrow. He taught us to turn to Allah in prayer. "
             "In the Quran, Allah comforts us: 'So verily, with every difficulty, there is relief' (Surah Ash-Sharh 94:5). "
             "Be gentle with yourself, keep praying, and know that Allah is close to the brokenhearted.";
    }

    if (lowercasePrompt.contains('salat') || lowercasePrompt.contains('prayer')) {
      return "As-Salamu Alaykum. Salat is the second pillar of Islam and a direct connection to Allah. "
             "Allah mentions in the Quran: 'Establish prayer, for indeed prayer prohibits immorality and wrongdoing' (Surah Al-Ankabut 29:45). "
             "The Prophet (peace be upon him) described Salat as the coolness of his eyes, emphasizing its importance and beauty.";
    }

    if (ragContext.isNotEmpty) {
      return "As-Salamu Alaykum. Based on the sacred texts: $ragContext. "
             "We should strive to understand and apply these teachings with sincerity, humility, and gentle manners, "
             "following the guidance of our Prophet Muhammad (peace be upon him).";
    }

    return "As-Salamu Alaykum. May Allah grant you peace and understanding. "
           "Please let me know which verse, Hadith, or topic you would like to explore, "
           "and we will discuss it in a respectful and gentle way.";
  }
}

final llmServiceProvider = Provider<LlmService>((ref) {
  final userRepo = ref.watch(userRepositoryProvider);
  return LlmService(userRepo);
});
