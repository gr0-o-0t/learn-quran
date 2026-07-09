import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llamadart/llamadart.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/rag_repository.dart';
import '../providers/repository_providers.dart';
import '../models/model_catalog.dart';
import 'model_download_service.dart';

/// Resolves a model, loads it if needed, and streams a chat completion — or
/// returns null if no model is available. Overridable for testing: the real
/// default resolves+loads the actual llama.cpp engine, which needs a real
/// multi-GB GGUF file no test environment has, so tests inject a fake that
/// never touches llamadart at all.
typedef ChatOrNullFn = Future<Stream<String>?> Function(
  String systemPrompt,
  String userPrompt,
  int maxTokens,
);

class LlmService {
  final UserRepository? _userRepo;
  final ModelDownloadService _downloadService;
  final ChatOrNullFn? _chatOverride;
  LlamaEngine? _engine;
  String? _loadedModelPath;

  LlmService([this._userRepo, ModelDownloadService? downloadService, ChatOrNullFn? chatOverride])
      : _downloadService = downloadService ?? ModelDownloadService(),
        _chatOverride = chatOverride;

  ChatOrNullFn get _chat => _chatOverride ?? _defaultChatOrNull;

  /// Resolves the user's selected model (or the RAM-based recommendation if
  /// nothing's been explicitly selected), then returns its local file path
  /// if it's actually downloaded — or null if it isn't (or if resolving that
  /// even fails, e.g. no platform plugin binding available), so callers
  /// always have a safe mock/no-model fallback rather than crashing.
  Future<String?> getSelectedModelPath() async {
    try {
      final model = await _resolveSelectedModel();
      if (await _downloadService.isDownloaded(model)) {
        return _downloadService.localPathFor(model);
      }
    } catch (_) {}
    return null;
  }

  Future<ModelInfo> _resolveSelectedModel() async {
    if (_userRepo != null) {
      final selectedId = await _userRepo.getEngagementValue('selected_llm_model');
      if (selectedId != null) {
        return modelById(selectedId);
      }
    }
    return recommendedModelFor(detectDeviceRamGb());
  }

  /// Reads total device RAM from `/proc/meminfo`, which is world-readable
  /// on both desktop Linux and Android (both are Linux-kernel-based) —
  /// no platform-specific plugin or permission needed. Falls back to a
  /// conservative 4.0GB estimate on any other platform or read failure.
  double detectDeviceRamGb() {
    try {
      if (Platform.isLinux || Platform.isAndroid) {
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

  /// Loads (or reuses an already-loaded) llama.cpp engine for [modelPath].
  /// Returns null if loading fails for any reason (corrupt file, OOM,
  /// unsupported quantization, ...), so callers fall back to mock responses
  /// instead of crashing the whole Q&A flow.
  Future<LlamaEngine?> _ensureEngine(String modelPath) async {
    if (_engine != null && _loadedModelPath == modelPath) {
      return _engine;
    }

    if (_engine != null) {
      await _engine!.dispose();
      _engine = null;
      _loadedModelPath = null;
    }

    try {
      final engine = LlamaEngine(LlamaBackend());
      await engine.loadModel(modelPath, modelParams: const ModelParams(contextSize: 4096));
      _engine = engine;
      _loadedModelPath = modelPath;
      return engine;
    } catch (_) {
      _engine = null;
      _loadedModelPath = null;
      return null;
    }
  }

  Future<Stream<String>?> _defaultChatOrNull(String systemPrompt, String userPrompt, int maxTokens) async {
    final modelPath = await getSelectedModelPath();
    final engine = modelPath == null ? null : await _ensureEngine(modelPath);
    if (engine == null) return null;
    return _streamChat(engine, systemPrompt, userPrompt, maxTokens);
  }

  Stream<String> _streamChat(LlamaEngine engine, String systemPrompt, String userPrompt, int maxTokens) async* {
    final messages = [
      LlamaChatMessage.fromText(role: LlamaChatRole.system, text: systemPrompt),
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: userPrompt),
    ];
    final responseStream = engine.create(
      messages,
      params: GenerationParams(maxTokens: maxTokens, temp: 0.7, topP: 0.9),
    );
    await for (final chunk in responseStream) {
      final text = chunk.choices.isNotEmpty ? chunk.choices.first.delta.content : null;
      if (text != null && text.isNotEmpty) {
        yield text;
      }
    }
  }

  /// Releases the loaded model's native resources. Call when the owning
  /// provider is disposed (app teardown / hot restart).
  Future<void> dispose() async {
    await _engine?.dispose();
    _engine = null;
    _loadedModelPath = null;
  }

  /// Single-pass generation: streams a response for [prompt], grounded in
  /// [ragContext] if non-empty. Falls back to a hardcoded mock response if
  /// no model is downloaded/loaded. Used directly by DailyStoryService (no
  /// RAG involved there) and as the final "refine" pass of
  /// [generateGroundedResponseStream].
  Stream<String> generateResponseStream(String prompt, String ragContext) async* {
    final chatStream = await _chat(_systemPrompt(ragContext), prompt, 512);
    if (chatStream == null) {
      final responseText = _generateMockResponse(prompt, ragContext);
      final words = responseText.split(' ');
      for (final word in words) {
        await Future.delayed(const Duration(milliseconds: 50));
        yield '$word ';
      }
      return;
    }
    yield* chatStream;
  }

  /// RAG-grounded generation for the Q&A screen: hybrid retrieval
  /// ([ragRepository.search]) on the raw [question], then a single-pass
  /// [generateResponseStream] grounded in the retrieved references.
  ///
  /// This used to run a hidden "draft" LLM pass first (HyDE-style query
  /// rewriting: draft a hypothetical answer, retrieve using that instead of
  /// the raw question) — removed. It cost a full extra LLM generation per
  /// question (measurably too slow on low-RAM phones), and a bad or
  /// hallucinated draft could misdirect retrieval — a plausible cause of
  /// reported "wrong citation" cases, since the draft was never grounded in
  /// anything. RagRepository's hybrid embedding+BM25+reranking search
  /// (see rag_repository.dart) is now relied on directly to handle the raw
  /// question well.
  Stream<String> generateGroundedResponseStream(
    String question, {
    required RagRepository ragRepository,
    void Function(List<RagSearchResult> ragResults)? onRetrieved,
  }) async* {
    final ragResults = await ragRepository.search(question, limit: 5);
    onRetrieved?.call(ragResults);
    final ragContext = _buildRagContext(ragResults);

    yield* generateResponseStream(question, ragContext);
  }

  String _buildRagContext(List<RagSearchResult> results) {
    final buffer = StringBuffer();
    for (final result in results) {
      final citation = citationFor(result);
      buffer.writeln('[${citation.title}] ${citation.text}');
    }
    return buffer.toString();
  }

  /// Encodes Rules.md's theological/AI generation rules (Sunnah Teaching
  /// Methodology, Zero-Hallucination Policy, Citations Required) as a system
  /// prompt for real on-device inference — the mock path already hardcodes
  /// this tone, so this keeps behavior consistent once a real model answers.
  String _systemPrompt(String ragContext) {
    final buffer = StringBuffer()
      ..writeln(
        'You are a gentle, respectful Islamic teaching companion for the Learn Quran app.',
      )
      ..writeln(
        'Always respond with warmth and clarity, in the manner of the Sunnah — '
        'never harsh, condescending, or clinical.',
      )
      ..writeln(
        'Base your answer only on the reference material below. If it does not '
        'contain enough information to answer, politely say you do not have '
        'enough information from your local sources rather than guessing.',
      )
      ..writeln(
        'When you use a verse or hadith from the material, cite it using the '
        'label given in brackets before it, for example "[Surah Al-Baqarah 2:153]".',
      );

    if (ragContext.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Reference material:')
        ..writeln(ragContext);
    }
    return buffer.toString();
  }

  String _generateMockResponse(String prompt, String ragContext) {
    final lowercasePrompt = prompt.toLowerCase();

    if (lowercasePrompt.contains('reflection') || lowercasePrompt.contains('story')) {
      return 'Title: Finding Calm in Patience\n\n'
             'As-Salamu Alaykum. In the journey of life, we often face moments of doubt and tiredness. '
             'However, every verse you read and every Salat you pray brings you closer to divine light. '
             'Remember, patience is a source of strength, and your consistency is beautiful to the Almighty. '
             'Keep moving forward with a peaceful heart, knowing that with every difficulty comes ease.';
    }

    if (lowercasePrompt.contains('patience') || lowercasePrompt.contains('sabr')) {
      return 'As-Salamu Alaykum. Patience (Sabr) is a beautiful virtue in Islam. '
             "Allah says in the Quran, 'Indeed, Allah is with the patient' (Surah Al-Baqarah 2:153). "
             'The Prophet Muhammad (peace be upon him) demonstrated patience throughout his life, '
             'responding to difficulties with calmness and prayers for those who opposed him. '
             "When facing adversity, we are encouraged to remain steadfast, trust in Allah's wisdom, and pray.";
    }

    if (lowercasePrompt.contains('sadness') || lowercasePrompt.contains('grief') || lowercasePrompt.contains('sorrow')) {
      return 'As-Salamu Alaykum. It is natural to feel sadness. Even the Prophet Muhammad (peace be upon him) experienced grief, '
             'such as during the Year of Sorrow. He taught us to turn to Allah in prayer. '
             "In the Quran, Allah comforts us: 'So verily, with every difficulty, there is relief' (Surah Ash-Sharh 94:5). "
             'Be gentle with yourself, keep praying, and know that Allah is close to the brokenhearted.';
    }

    if (lowercasePrompt.contains('salat') || lowercasePrompt.contains('prayer')) {
      return 'As-Salamu Alaykum. Salat is the second pillar of Islam and a direct connection to Allah. '
             "Allah mentions in the Quran: 'Establish prayer, for indeed prayer prohibits immorality and wrongdoing' (Surah Al-Ankabut 29:45). "
             'The Prophet (peace be upon him) described Salat as the coolness of his eyes, emphasizing its importance and beauty.';
    }

    if (ragContext.isNotEmpty) {
      return 'As-Salamu Alaykum. Based on the sacred texts: $ragContext. '
             'We should strive to understand and apply these teachings with sincerity, humility, and gentle manners, '
             'following the guidance of our Prophet Muhammad (peace be upon him).';
    }

    return 'As-Salamu Alaykum. May Allah grant you peace and understanding. '
           'Please let me know which verse, Hadith, or topic you would like to explore, '
           'and we will discuss it in a respectful and gentle way.';
  }
}

final llmServiceProvider = Provider<LlmService>((ref) {
  final userRepo = ref.watch(userRepositoryProvider);
  final service = LlmService(userRepo);
  ref.onDispose(() => service.dispose());
  return service;
});
