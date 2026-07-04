import 'package:drift/drift.dart';
import '../local/db/app_database.dart';

class UserRepository {
  final AppDatabase _db;

  UserRepository(this._db);

  // --- Reading Progress ---
  Future<void> updateReadingProgress(int surahNumber, int ayahNumber) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final existing = await (_db.select(_db.userProgress)
          ..where((t) =>
              t.surahNumber.equals(surahNumber) &
              t.ayahNumber.equals(ayahNumber)))
        .getSingleOrNull();

    if (existing != null) {
      await (_db.update(_db.userProgress)
            ..where((t) => t.id.equals(existing.id)))
          .write(UserProgressCompanion(
        lastReadTimestamp: Value(now),
      ));
    } else {
      await _db.into(_db.userProgress).insert(UserProgressCompanion.insert(
            surahNumber: surahNumber,
            ayahNumber: ayahNumber,
            lastReadTimestamp: now,
          ));
    }
  }

  Future<List<UserProgressData>> getBookmarks() {
    return (_db.select(_db.userProgress)
          ..where((t) => t.bookmarkFolder.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.lastReadTimestamp)]))
        .get();
  }

  Future<void> toggleBookmark(
      int surahNumber, int ayahNumber, String? folder) async {
    final existing = await (_db.select(_db.userProgress)
          ..where((t) =>
              t.surahNumber.equals(surahNumber) &
              t.ayahNumber.equals(ayahNumber)))
        .getSingleOrNull();

    if (existing != null) {
      await (_db.update(_db.userProgress)
            ..where((t) => t.id.equals(existing.id)))
          .write(UserProgressCompanion(
        bookmarkFolder: Value(folder),
      ));
    } else {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _db.into(_db.userProgress).insert(UserProgressCompanion.insert(
            surahNumber: surahNumber,
            ayahNumber: ayahNumber,
            lastReadTimestamp: now,
            bookmarkFolder: Value(folder),
          ));
    }
  }

  // --- Salat Logs ---
  Future<SalatLog?> getSalatLogForDate(String date) {
    return (_db.select(_db.salatLogs)
          ..where((t) => t.date.equals(date)))
        .getSingleOrNull();
  }

  Future<void> updateSalatLog(
      String date, String prayer, bool completed) async {
    final existing = await getSalatLogForDate(date);

    if (existing == null) {
      final companion = SalatLogsCompanion.insert(
        date: date,
        fajrCompleted: Value(prayer == 'fajr' ? completed : false),
        dhuhrCompleted: Value(prayer == 'dhuhr' ? completed : false),
        asrCompleted: Value(prayer == 'asr' ? completed : false),
        maghribCompleted: Value(prayer == 'maghrib' ? completed : false),
        ishaCompleted: Value(prayer == 'isha' ? completed : false),
      );
      await _db.into(_db.salatLogs).insert(companion);
    } else {
      final update = <String, Value<bool>>{};
      switch (prayer) {
        case 'fajr':
          update['fajrCompleted'] = Value(completed);
          break;
        case 'dhuhr':
          update['dhuhrCompleted'] = Value(completed);
          break;
        case 'asr':
          update['asrCompleted'] = Value(completed);
          break;
        case 'maghrib':
          update['maghribCompleted'] = Value(completed);
          break;
        case 'isha':
          update['ishaCompleted'] = Value(completed);
          break;
      }

      await (_db.update(_db.salatLogs)..where((t) => t.date.equals(date)))
          .write(SalatLogsCompanion(
        fajrCompleted:
            prayer == 'fajr' ? Value(completed) : const Value.absent(),
        dhuhrCompleted:
            prayer == 'dhuhr' ? Value(completed) : const Value.absent(),
        asrCompleted:
            prayer == 'asr' ? Value(completed) : const Value.absent(),
        maghribCompleted:
            prayer == 'maghrib' ? Value(completed) : const Value.absent(),
        ishaCompleted:
            prayer == 'isha' ? Value(completed) : const Value.absent(),
      ));
    }
  }

  Future<List<SalatLog>> getAllSalatLogs() {
    return (_db.select(_db.salatLogs)
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .get();
  }

  // --- Engagement State ---
  Future<String?> getEngagementValue(String key) async {
    final row = await (_db.select(_db.userEngagementState)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setEngagementValue(String key, String value) async {
    await _db
        .into(_db.userEngagementState)
        .insertOnConflictUpdate(UserEngagementStateCompanion.insert(
          key: key,
          value: value,
        ));
  }

  Future<void> clearAllData() async {
    await _db.delete(_db.userProgress).go();
    await _db.delete(_db.salatLogs).go();
    await _db.delete(_db.conversations).go();
    await _db.delete(_db.messages).go();
    await _db.delete(_db.userEngagementState).go();
  }
}
