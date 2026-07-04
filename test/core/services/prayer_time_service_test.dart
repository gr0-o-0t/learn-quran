import 'package:flutter_test/flutter_test.dart';
import 'package:adhan/adhan.dart';
import 'package:learn_quran/core/services/prayer_time_service.dart';

void main() {
  late PrayerTimeService service;

  setUp(() {
    service = PrayerTimeService();
  });

  group('PrayerTimeService', () {
    test('calculates prayer times for Dhaka coordinates', () {
      final times = service.calculatePrayerTimes(
        latitude: 23.8103,
        longitude: 90.4125,
        method: CalculationMethod.karachi,
        madhab: Madhab.hanafi,
        date: DateTime(2026, 6, 14),
      );

      expect(times.fajr, isNotNull);
      expect(times.dhuhr, isNotNull);
      expect(times.asr, isNotNull);
      expect(times.maghrib, isNotNull);
      expect(times.isha, isNotNull);

      // Fajr should be before sunrise
      expect(times.fajr.isBefore(times.sunrise), isTrue);
      // Dhuhr should be before Asr
      expect(times.dhuhr.isBefore(times.asr), isTrue);
      // Asr should be before Maghrib
      expect(times.asr.isBefore(times.maghrib), isTrue);
      // Maghrib should be before Isha
      expect(times.maghrib.isBefore(times.isha), isTrue);
    });

    test('calculates prayer times for Mecca coordinates with Umm al-Qura method', () {
      final times = service.calculatePrayerTimes(
        latitude: 21.4225,
        longitude: 39.8262,
        method: CalculationMethod.umm_al_qura,
        madhab: Madhab.shafi,
        date: DateTime(2026, 1, 15),
      );

      expect(times.fajr, isNotNull);
      expect(times.fajr.isBefore(times.sunrise), isTrue);
      expect(times.dhuhr.isBefore(times.asr), isTrue);
    });

    test('returns correct method name strings', () {
      expect(service.getMethodName(CalculationMethod.muslim_world_league),
          'Muslim World League');
      expect(service.getMethodName(CalculationMethod.north_america),
          'ISNA (North America)');
      expect(service.getMethodName(CalculationMethod.karachi),
          'University of Islamic Sciences, Karachi');
      expect(service.getMethodName(CalculationMethod.umm_al_qura),
          'Umm al-Qura University, Makkah');
      expect(
          service.getMethodName(CalculationMethod.other), 'Other');
    });

    test('uses different madhab for Asr time', () {
      final hanafiTimes = service.calculatePrayerTimes(
        latitude: 23.8103,
        longitude: 90.4125,
        method: CalculationMethod.karachi,
        madhab: Madhab.hanafi,
        date: DateTime(2026, 6, 14),
      );

      final shafiTimes = service.calculatePrayerTimes(
        latitude: 23.8103,
        longitude: 90.4125,
        method: CalculationMethod.karachi,
        madhab: Madhab.shafi,
        date: DateTime(2026, 6, 14),
      );

      // Hanafi Asr is typically later than Shafi Asr
      expect(hanafiTimes.asr.isAfter(shafiTimes.asr), isTrue);
    });
  });
}
