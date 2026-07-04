import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:adhan/adhan.dart';
import '../../data/local/db/app_database.dart';
import '../../data/repositories/user_repository.dart';
import 'prayer_time_service.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
void recalculateDailyPrayersCallback() async {
  final db = AppDatabase();
  final userRepo = UserRepository(db);
  final prayerService = PrayerTimeService();
  final notifService = NotificationService();

  try {
    final methodStr = await userRepo.getEngagementValue('calculation_method') ?? 'muslim_world_league';
    final madhabStr = await userRepo.getEngagementValue('madhab') ?? 'hanafi';
    final latStr = await userRepo.getEngagementValue('latitude') ?? '23.8103'; // default Dhaka
    final lonStr = await userRepo.getEngagementValue('longitude') ?? '90.4125';

    final method = _parseMethod(methodStr);
    final madhab = _parseMadhab(madhabStr);
    final lat = double.parse(latStr);
    final lon = double.parse(lonStr);

    await notifService.initialize();
    await notifService.cancelAllNotifications();

    final today = DateTime.now();
    for (int i = 0; i < 2; i++) {
      final date = today.add(Duration(days: i));
      final times = prayerService.calculatePrayerTimes(
        latitude: lat,
        longitude: lon,
        method: method,
        madhab: madhab,
        date: date,
      );

      await notifService.schedulePrayerNotification('Fajr', times.fajr);
      await notifService.schedulePrayerNotification('Dhuhr', times.dhuhr);
      await notifService.schedulePrayerNotification('Asr', times.asr);
      await notifService.schedulePrayerNotification('Maghrib', times.maghrib);
      await notifService.schedulePrayerNotification('Isha', times.isha);
    }
  } catch (e) {
    // Fail silently or log
  } finally {
    await db.close();
  }
}

CalculationMethod _parseMethod(String str) {
  switch (str) {
    case 'muslim_world_league':
      return CalculationMethod.muslim_world_league;
    case 'north_america':
      return CalculationMethod.north_america;
    case 'umm_al_qura':
      return CalculationMethod.umm_al_qura;
    case 'karachi':
      return CalculationMethod.karachi;
    case 'egyptian':
      return CalculationMethod.egyptian;
    default:
      return CalculationMethod.muslim_world_league;
  }
}

Madhab _parseMadhab(String str) {
  return str == 'hanafi' ? Madhab.hanafi : Madhab.shafi;
}

class BackgroundWorkerService {
  // AndroidAlarmManager identifies alarms by int id; registering the same id
  // again cancels and replaces the existing one.
  static const int dailyPrayerAlarmId = 1001;
  static const int immediateRecalculationAlarmId = 1002;

  Future<void> initialize() async {
    await AndroidAlarmManager.initialize();
  }

  Future<void> scheduleDailyPrayerWorker() async {
    await AndroidAlarmManager.periodic(
      const Duration(hours: 24),
      dailyPrayerAlarmId,
      recalculateDailyPrayersCallback,
      rescheduleOnReboot: true,
    );
  }

  Future<void> triggerImmediateRecalculation() async {
    await AndroidAlarmManager.oneShot(
      Duration.zero,
      immediateRecalculationAlarmId,
      recalculateDailyPrayersCallback,
    );
  }
}
