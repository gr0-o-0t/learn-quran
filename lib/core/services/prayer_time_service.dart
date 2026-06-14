import 'package:adhan/adhan.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PrayerTimeService {
  // Calculates prayer times for a given date, coordinates, and calculation options
  PrayerTimes calculatePrayerTimes({
    required double latitude,
    required double longitude,
    required CalculationMethod method,
    required Madhab madhab,
    DateTime? date,
  }) {
    final coordinates = Coordinates(latitude, longitude);
    final parameters = method.getParameters()..madhab = madhab;
    final targetDate = date ?? DateTime.now();

    return PrayerTimes(
      coordinates,
      DateComponents.from(targetDate),
      parameters,
    );
  }

  // Returns human readable names for methods
  String getMethodName(CalculationMethod method) {
    switch (method) {
      case CalculationMethod.muslim_world_league:
        return 'Muslim World League';
      case CalculationMethod.egyptian:
        return 'Egyptian General Authority of Survey';
      case CalculationMethod.karachi:
        return 'University of Islamic Sciences, Karachi';
      case CalculationMethod.umm_al_qura:
        return 'Umm al-Qura University, Makkah';
      case CalculationMethod.dubai:
        return 'Dubai / Gulf Region';
      case CalculationMethod.moon_sighting_committee:
        return 'Moon Sighting Committee';
      case CalculationMethod.north_america:
        return 'ISNA (North America)';
      case CalculationMethod.singapore:
        return 'MUIS (Singapore)';
      case CalculationMethod.turkey:
        return 'Diyanet (Turkey)';
      case CalculationMethod.tehran:
        return 'Institute of Geophysics, University of Tehran';
      case CalculationMethod.kuwait:
        return 'Kuwait';
      case CalculationMethod.qatar:
        return 'Qatar';
      default:
        return 'Other';
    }
  }
}

// Riverpod Provider for PrayerTimeService
final prayerTimeServiceProvider = Provider<PrayerTimeService>((ref) {
  return PrayerTimeService();
});
