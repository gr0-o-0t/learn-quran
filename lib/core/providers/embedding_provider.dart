import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/embedding_service.dart';

final embeddingServiceProvider = Provider<EmbeddingService>((ref) {
  final service = EmbeddingService();
  ref.onDispose(() => service.dispose());
  return service;
});
