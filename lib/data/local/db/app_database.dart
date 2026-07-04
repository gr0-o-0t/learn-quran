import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite_vector/sqlite_vector.dart';

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

  /// Named constructor for tests — accepts any [QueryExecutor],
  /// typically `NativeDatabase.memory()`.
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  bool _hasVectorExtension = false;
  bool get hasVectorExtension => _hasVectorExtension;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createVirtualTable();
        },
        beforeOpen: (details) async {
          await _createVirtualTable();
        },
      );

  Future<void> _createVirtualTable() async {
    try {
      // Ensure the sqlite-vec extension is loaded
      sqlite3.loadSqliteVectorExtension();
    } catch (e) {
      // Ignore load error
    }

    try {
      // Check if vec0 module is registered in SQLite
      final moduleCheck = await customSelect("SELECT 1 FROM pragma_module_list WHERE name = 'vec0'").getSingleOrNull();
      _hasVectorExtension = moduleCheck != null;
    } catch (e) {
      _hasVectorExtension = false;
    }

    if (_hasVectorExtension) {
      try {
        await customStatement('''
          CREATE VIRTUAL TABLE IF NOT EXISTS vec_knowledge_base USING vec0(
            embedding float[384]
          );
        ''');
      } catch (e) {
        _hasVectorExtension = false;
        await _createFallbackTable();
      }
    } else {
      await _createFallbackTable();
    }
  }

  Future<void> _createFallbackTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS vec_knowledge_base (
        rowid INTEGER PRIMARY KEY,
        embedding BLOB
      );
    ''');
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));

    if (!await file.exists()) {
      try {
        // Create directory if not exists
        await Directory(dbFolder.path).create(recursive: true);
        // Load database from assets and copy to local sandbox
        final data = await rootBundle.load('assets/databases/quran_base.db');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await file.writeAsBytes(bytes);
      } catch (e) {
        // Fallback: file will be created as a new empty database by NativeDatabase
      }
    }

    return NativeDatabase.createInBackground(file);
  });
}
