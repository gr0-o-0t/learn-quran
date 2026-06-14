import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

// 1. Read-Only Knowledge Base Tables
class Verses extends Table {
  IntColumn get id => integer()();
  IntColumn get surahNumber => integer()();
  IntColumn get ayahNumber => integer()();
  IntColumn get juzNumber => integer()();
  TextColumn get arabicText => text()();
  TextColumn get englishText => text()();
  TextColumn get banglaText => text()();
  TextColumn get hindiText => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Hadiths extends Table {
  IntColumn get id => integer()();
  TextColumn get bookName => text()();
  TextColumn get hadithNumber => text()();
  TextColumn get chapterTitle => text()();
  TextColumn get arabicText => text()();
  TextColumn get englishText => text()();
  TextColumn get banglaText => text()();
  TextColumn get hindiText => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tafsirs extends Table {
  IntColumn get id => integer()();
  IntColumn get surahNumber => integer()();
  IntColumn get ayahNumber => integer()();
  TextColumn get author => text()();
  TextColumn get contentEnglish => text()();
  TextColumn get contentBangla => text()();
  TextColumn get contentHindi => text()();

  @override
  Set<Column> get primaryKey => {id};
}

// 2. Writable User Data Tables
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

// 3. Database initialization
@DriftDatabase(tables: [
  Verses,
  Hadiths,
  Tafsirs,
  UserProgress,
  SalatLogs,
  Conversations,
  Messages,
  UserEngagementState,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
