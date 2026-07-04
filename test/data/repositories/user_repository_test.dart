import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:learn_quran/data/local/db/app_database.dart';
import 'package:learn_quran/data/repositories/user_repository.dart';

void main() {
  late AppDatabase db;
  late UserRepository repository;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = UserRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('UserRepository Tests', () {
    test('updateReadingProgress inserts or updates user reading progress', () async {
      await repository.updateReadingProgress(1, 1);
      final records = await db.select(db.userProgress).get();
      expect(records.length, 1);
      expect(records[0].surahNumber, 1);
      expect(records[0].ayahNumber, 1);

      // Updating again should modify the existing record timestamp
      final initialTimestamp = records[0].lastReadTimestamp;
      await Future.delayed(const Duration(seconds: 1));
      await repository.updateReadingProgress(1, 1);
      final updatedRecords = await db.select(db.userProgress).get();
      expect(updatedRecords.length, 1);
      expect(updatedRecords[0].lastReadTimestamp, greaterThanOrEqualTo(initialTimestamp));
    });

    test('toggleBookmark and getBookmarks works as expected', () async {
      // Toggle bookmark ON
      await repository.toggleBookmark(2, 5, 'Favorites');
      final bookmarks = await repository.getBookmarks();
      expect(bookmarks.length, 1);
      expect(bookmarks[0].surahNumber, 2);
      expect(bookmarks[0].ayahNumber, 5);
      expect(bookmarks[0].bookmarkFolder, 'Favorites');

      // Toggle bookmark OFF (set folder to null)
      await repository.toggleBookmark(2, 5, null);
      final emptyBookmarks = await repository.getBookmarks();
      expect(emptyBookmarks, isEmpty);
    });

    test('updateSalatLog and getSalatLogForDate works as expected', () async {
      const dateStr = '2026-06-14';
      
      // Get log for empty date
      final initialLog = await repository.getSalatLogForDate(dateStr);
      expect(initialLog, isNull);

      // Set fajr completed
      await repository.updateSalatLog(dateStr, 'fajr', true);
      var log = await repository.getSalatLogForDate(dateStr);
      expect(log, isNotNull);
      expect(log!.fajrCompleted, isTrue);
      expect(log.dhuhrCompleted, isFalse);

      // Set dhuhr completed
      await repository.updateSalatLog(dateStr, 'dhuhr', true);
      log = await repository.getSalatLogForDate(dateStr);
      expect(log, isNotNull);
      expect(log!.fajrCompleted, isTrue);
      expect(log.dhuhrCompleted, isTrue);

      // Set fajr back to uncompleted
      await repository.updateSalatLog(dateStr, 'fajr', false);
      log = await repository.getSalatLogForDate(dateStr);
      expect(log, isNotNull);
      expect(log!.fajrCompleted, isFalse);
      expect(log.dhuhrCompleted, isTrue);
    });

    test('get/set engagement value works', () async {
      final initialVal = await repository.getEngagementValue('streak');
      expect(initialVal, isNull);

      await repository.setEngagementValue('streak', '5');
      final updatedVal = await repository.getEngagementValue('streak');
      expect(updatedVal, '5');

      // Update same key
      await repository.setEngagementValue('streak', '6');
      final finalVal = await repository.getEngagementValue('streak');
      expect(finalVal, '6');
    });
  });
}
