import 'package:workmanager/workmanager.dart';
import 'package:adhan/adhan.dart';
import '../../data/local/db/app_database.dart';
import '../../data/repositories/user_repository.dart';
import 'prayer_time_service.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
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

    return true;
  });
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
  static const String uniqueName = 'learn_quran_daily_prayers';
  static const String taskName = 'recalculate_daily_prayers';

  Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  Future<void> scheduleDailyPrayerWorker() async {
    await Workmanager().registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: const Duration(hours: 24),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  Future<void> triggerImmediateRecalculation() async {
    await Workmanager().registerOneOffTask(
      '${uniqueName}_one_off',
      taskName,
    );
  }
}
