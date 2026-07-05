import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/local/db/app_database.dart';
import '../../data/local/db/knowledge_base_database.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final knowledgeBaseDatabaseProvider = Provider<KnowledgeBaseDatabase>((ref) {
  throw UnsupportedError(
    'knowledgeBaseDatabaseProvider must be overridden via '
    'ProviderScope at app startup (see main.dart) — it needs an async '
    'path_provider lookup that a synchronous Provider body cannot perform.',
  );
});

/// Resolves the writable path KnowledgeBaseDatabase copies the bundled (or
/// downloaded) kb.db to, and opens it. Called once from main() before
/// runApp(), with the result passed in via ProviderScope overrides —
/// mirrors how `AppDatabase`'s file lives in ApplicationDocumentsDirectory,
/// but this needs to run before the widget tree exists since Drift's
/// LazyDatabase pattern doesn't fit an asset-copy-then-open flow as cleanly
/// as a direct async open here.
Future<KnowledgeBaseDatabase> openKnowledgeBaseDatabase() async {
  final docsDir = await getApplicationDocumentsDirectory();
  return KnowledgeBaseDatabase.openBundled(
    assetPath: 'assets/databases/kb.db',
    destinationPath: '${docsDir.path}/kb.sqlite',
  );
}
