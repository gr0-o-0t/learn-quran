import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

class UserProgress extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get surahNumber => integer()();
  IntColumn get ayahNumber => integer()();
  IntColumn get lastReadTimestamp => integer()();
  BoolColumn get isMemorized => boolean().withDefault(const Constant(false))();
  TextColumn get bookmarkFolder => text().nullable()();
}

class SalatLogs extends Table {
  TextColumn get date => text()(); // YYYY-MM-DD
  BoolColumn get fajrCompleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dhuhrCompleted => boolean().withDefault(const Constant(false))();
  BoolColumn get asrCompleted => boolean().withDefault(const Constant(false))();
  BoolColumn get maghribCompleted => boolean().withDefault(const Constant(false))();
  BoolColumn get ishaCompleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {date};
}

class Conversations extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get title => text()();
  IntColumn get createdAt => integer()();
  IntColumn get lastActive => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Messages extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get conversationId => text().references(Conversations, #id, onDelete: KeyAction.cascade)();
  TextColumn get sender => text()(); // 'user' or 'agent'
  TextColumn get textContent => text()();
  TextColumn get citationsJson => text()(); // Serialized array of sources
  IntColumn get timestamp => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class UserEngagementState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [
  UserProgress,
  SalatLogs,
  Conversations,
  Messages,
  UserEngagementState,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Named constructor for tests — accepts any [QueryExecutor],
  /// typically `NativeDatabase.memory()`.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2; // Bumped: v1 also held Verses/Hadiths/Tafsirs,
  // now split into the separate KnowledgeBaseDatabase (see Task 3/7 of
  // docs/superpowers/plans/2026-07-05-knowledge-base-v1.md). No migration
  // path from v1 is provided — no production users exist on the old
  // content-mixed schema.
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
