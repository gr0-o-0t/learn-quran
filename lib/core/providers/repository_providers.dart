import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/quran_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/rag_repository.dart';
import 'database_provider.dart';
import 'embedding_provider.dart';
import '../services/engagement_service.dart';
import '../services/daily_story_service.dart';
import '../services/llm_service.dart';

final quranRepositoryProvider = Provider<QuranRepository>((ref) {
  return QuranRepository(ref.watch(knowledgeBaseDatabaseProvider));
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(ref.watch(appDatabaseProvider));
});

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  return ConversationRepository(ref.watch(appDatabaseProvider));
});

final ragRepositoryProvider = Provider<RagRepository>((ref) {
  return RagRepository(
    ref.watch(knowledgeBaseDatabaseProvider),
    ref.watch(embeddingServiceProvider),
  );
});

final engagementServiceProvider = Provider<EngagementService>((ref) {
  final userRepo = ref.watch(userRepositoryProvider);
  final quranRepo = ref.watch(quranRepositoryProvider);
  return EngagementService(userRepo, quranRepo);
});

final dailyStoryServiceProvider = Provider<DailyStoryService>((ref) {
  final userRepo = ref.watch(userRepositoryProvider);
  final llmService = ref.watch(llmServiceProvider);
  return DailyStoryService(userRepo, llmService);
});

