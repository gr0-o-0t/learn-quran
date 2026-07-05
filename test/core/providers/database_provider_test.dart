import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:learn_quran/core/providers/database_provider.dart';
import 'package:learn_quran/data/local/db/knowledge_base_database.dart';

/// Mirrors main.dart's `knowledgeBaseDatabaseProvider.overrideWith(...)`
/// override exactly: reuse the already-opened [initial] db on the first
/// build, then re-open from [path] on every later rebuild (triggered by
/// `ref.invalidate` after Settings downloads a fresh kb.db).
dynamic _kbOverride({
  required KnowledgeBaseDatabase initial,
  required String path,
  required void Function(KnowledgeBaseDatabase) onClosed,
}) {
  KnowledgeBaseDatabase? next = initial;
  return knowledgeBaseDatabaseProvider.overrideWith((ref) {
    final db = next ?? KnowledgeBaseDatabase.fromFile(path);
    next = null;
    ref.onDispose(() {
      onClosed(db);
      db.close();
    });
    return db;
  });
}

void main() {
  late Directory tempDir;
  late String kbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kb_provider_test');
    kbPath = p.join(tempDir.path, 'kb.db');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('invalidating re-opens a fresh instance from the same path and closes the previous one', () async {
    final closed = <KnowledgeBaseDatabase>[];
    final container = ProviderContainer(
      overrides: [
        _kbOverride(
          initial: KnowledgeBaseDatabase.fromFile(kbPath),
          path: kbPath,
          onClosed: closed.add,
        ),
      ],
    );
    addTearDown(container.dispose);

    final firstDb = container.read(knowledgeBaseDatabaseProvider);
    container.invalidate(knowledgeBaseDatabaseProvider);
    final secondDb = container.read(knowledgeBaseDatabaseProvider);

    expect(identical(firstDb, secondDb), isFalse);
    expect(closed, contains(firstDb));
    expect(closed, isNot(contains(secondDb)));
  });

  test('dependents watching the provider rebuild against the fresh instance', () async {
    final closed = <KnowledgeBaseDatabase>[];
    final container = ProviderContainer(
      overrides: [
        _kbOverride(
          initial: KnowledgeBaseDatabase.fromFile(kbPath),
          path: kbPath,
          onClosed: closed.add,
        ),
      ],
    );
    addTearDown(container.dispose);

    final dependentProvider = Provider((ref) => ref.watch(knowledgeBaseDatabaseProvider));
    container.listen(dependentProvider, (_, __) {}, fireImmediately: true);

    final before = container.read(dependentProvider);
    container.invalidate(knowledgeBaseDatabaseProvider);
    final after = container.read(dependentProvider);

    expect(identical(before, after), isFalse);
  });
}
