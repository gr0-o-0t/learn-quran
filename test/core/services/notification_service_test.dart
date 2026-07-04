import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:learn_quran/core/services/notification_service.dart';

class FakeFlutterLocalNotificationsPlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  bool initialized = false;
  final List<Map<String, dynamic>> scheduled = [];
  bool cancelledAll = false;
  final List<int> cancelledIds = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #initialize) {
      initialized = true;
      return Future.value(true);
    }
    if (invocation.memberName == #zonedSchedule) {
      final named = invocation.namedArguments;
      scheduled.add({
        'id': named[#id] as int,
        'title': named[#title] as String?,
        'body': named[#body] as String?,
        'date': named[#scheduledDate] as DateTime,
      });
      return Future.value();
    }
    if (invocation.memberName == #cancel) {
      final named = invocation.namedArguments;
      cancelledIds.add(named[#id] as int);
      return Future.value();
    }
    if (invocation.memberName == #cancelAll) {
      cancelledAll = true;
      return Future.value();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  late FakeFlutterLocalNotificationsPlugin fakePlugin;
  late NotificationService service;

  setUp(() {
    fakePlugin = FakeFlutterLocalNotificationsPlugin();
    service = NotificationService.withPlugin(fakePlugin);
  });

  group('NotificationService Tests', () {
    test('initialize initializes the plugin', () async {
      expect(fakePlugin.initialized, isFalse);
      await service.initialize();
      expect(fakePlugin.initialized, isTrue);
    });

    test('schedulePrayerNotification schedules future notifications and skips past ones', () async {
      final now = DateTime.now();
      final futureTime = now.add(const Duration(hours: 2));
      final pastTime = now.subtract(const Duration(hours: 2));

      // Schedule a future one
      await service.schedulePrayerNotification('Fajr', futureTime);
      expect(fakePlugin.scheduled.length, 1);
      expect(fakePlugin.scheduled[0]['title'], 'Prayer Time: Fajr');
      expect(fakePlugin.scheduled[0]['body'], 'It is time for Fajr prayer.');
      expect((fakePlugin.scheduled[0]['date'] as DateTime).isAtSameMomentAs(futureTime), isTrue);

      // Schedule a past one (should skip)
      await service.schedulePrayerNotification('Dhuhr', pastTime);
      expect(fakePlugin.scheduled.length, 1); // remains 1
    });

    test('cancelAllNotifications cancels all', () async {
      expect(fakePlugin.cancelledAll, isFalse);
      await service.cancelAllNotifications();
      expect(fakePlugin.cancelledAll, isTrue);
    });

    test('cancelNotification cancels by id', () async {
      await service.cancelNotification(123);
      expect(fakePlugin.cancelledIds, contains(123));
    });
  });

  group('Permission methods on non-Android (real plugin)', () {
    test('requestNotificationsPermission returns null off Android', () async {
      final realService = NotificationService();
      final result = await realService.requestNotificationsPermission();
      expect(result, isNull);
    });

    test('requestExactAlarmsPermission returns null off Android', () async {
      final realService = NotificationService();
      final result = await realService.requestExactAlarmsPermission();
      expect(result, isNull);
    });

    test('areNotificationsEnabled returns null off Android', () async {
      final realService = NotificationService();
      final result = await realService.areNotificationsEnabled();
      expect(result, isNull);
    });

    test('canScheduleExactNotifications returns null off Android', () async {
      final realService = NotificationService();
      final result = await realService.canScheduleExactNotifications();
      expect(result, isNull);
    });
  });
}
