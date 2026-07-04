import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Service for scheduling and managing local notifications, primarily for
/// prayer time reminders.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  NotificationService() : _plugin = FlutterLocalNotificationsPlugin();

  /// For testing: inject a mock plugin.
  NotificationService.withPlugin(this._plugin);

  /// Initializes the notification plugin. Must be called before scheduling.
  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(settings: initSettings);
    _initialized = true;
  }

  /// Schedules a prayer time notification.
  ///
  /// [prayerName] — e.g. "Fajr", "Dhuhr"
  /// [time] — the DateTime when the prayer starts
  Future<void> schedulePrayerNotification(
    String prayerName,
    DateTime time,
  ) async {
    if (!_initialized) await initialize();

    // Skip notifications for past times
    if (time.isBefore(DateTime.now())) return;

    // Generate a unique ID from the prayer name hash + date
    final id = '${prayerName}_${time.toIso8601String()}'.hashCode;

    const androidDetails = AndroidNotificationDetails(
      'prayer_times', // channel id
      'Prayer Times', // channel name
      channelDescription: 'Notifications for prayer time reminders',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      id: id,
      title: 'Prayer Time: $prayerName',
      body: 'It is time for $prayerName prayer.',
      scheduledDate: tz.TZDateTime.from(time, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// Cancels all pending notifications.
  Future<void> cancelAllNotifications() async {
    await _plugin.cancelAll();
  }

  /// Cancels a specific notification by its ID.
  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id: id);
  }
}

/// Riverpod provider for NotificationService.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});
