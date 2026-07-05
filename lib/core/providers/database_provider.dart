import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/db/app_database.dart';
import '../../data/local/db/knowledge_base_database.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final knowledgeBaseDatabaseProvider = Provider<KnowledgeBaseDatabase>((ref) {
  // Task 8 (Settings + KbDownloadService) wires this to the real bundled/
  // downloaded kb.db path; until then this throws if constructed directly.
  throw UnimplementedError(
    'knowledgeBaseDatabaseProvider is wired up in Task 8 — see '
    'docs/superpowers/plans/2026-07-05-knowledge-base-v1.md',
  );
});
