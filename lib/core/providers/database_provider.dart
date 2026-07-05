import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/db/app_database.dart';
import '../../data/local/db/knowledge_base_database.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// Overridden in `main.dart` via `overrideWith` (not `overrideWithValue`) so
/// `ref.invalidate(knowledgeBaseDatabaseProvider)` re-opens the database from
/// the same on-disk path after Settings downloads a fresh `kb.db` — dependents
/// that `ref.watch` this (`quranRepositoryProvider`, `ragRepositoryProvider`)
/// then rebuild against the new instance without an app restart.
///
/// The knowledge base is no longer bundled as an app asset — `kb.db` is
/// ~247MB and GitHub hard-rejects any git-tracked file over 100MB, so it is
/// download-required instead (see `KbDownloadService`, the `kb-v*` release
/// pipeline, and the Settings "Knowledge Base" section). If nothing has been
/// downloaded yet, `KnowledgeBaseDatabase.fromFile` creates a fresh, empty
/// (schema-only) database via Drift's `onCreate` migration rather than
/// failing — there is simply no file there yet. `QuranRepository` and
/// `RagRepository` callers detect this empty case via a row count (see
/// `QuranRepository.hasContent()`) and show a setup prompt rather than
/// treating it as an error.
final knowledgeBaseDatabaseProvider = Provider<KnowledgeBaseDatabase>((ref) {
  throw UnsupportedError(
    'knowledgeBaseDatabaseProvider must be overridden via '
    'ProviderScope at app startup (see main.dart) — it needs an async '
    'path_provider lookup that a synchronous Provider body cannot perform.',
  );
});
