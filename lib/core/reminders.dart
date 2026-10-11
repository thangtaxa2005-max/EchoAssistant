import 'package:drift/drift.dart' show Value;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';

@pragma('vm:entry-point')
Future<void> notificationActionBackground(NotificationResponse response) async {
  final id = response.payload;
  if (id == null) return;
  final db = AppDatabase();
  try {
    final task = await db.taskById(id);
    if (task == null) return;
    final service = ReminderService(db);
    await service.initialize(requestPermissions: false);
    await service.applyAction(task, response.actionId ?? '');
  } finally {
    await db.close();
  }
}

class ReminderService {
  ReminderService(this.db);

  final AppDatabase db;
  final plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize({bool requestPermissions = true}) async {
    tzdata.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
    }
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) async {
        final task = await db.taskById(response.payload ?? '');
        if (task != null) await applyAction(task, response.actionId ?? '');
      },
      onDidReceiveBackgroundNotificationResponse: notificationActionBackground,
    );
    if (requestPermissions) {
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
    }
  }

  int _notificationId(String id, int index) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x3fffffff;
    }
    return ((hash % 500000000) * 2) + index;
  }

  Future<void> cancel(String id) async {
    await plugin.cancel(_notificationId(id, 0));
    await plugin.cancel(_notificationId(id, 1));
  }

  Future<void> schedule(Task task) async {
    await cancel(task.id);
    if (task.status != 'pending') return;
    final due = DateTime.fromMillisecondsSinceEpoch(task.dueAt);
    if (!due.isAfter(DateTime.now())) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'echo_reminders',
        'Nhắc việc Echo',
        channelDescription: 'Nhắc đúng giờ và giục lại sau 10 phút',
        importance: Importance.max,
        priority: Priority.high,
        actions: const [
          AndroidNotificationAction('done', 'Xong'),
          AndroidNotificationAction('snooze', 'Lùi 15p'),
          AndroidNotificationAction('skip', 'Bỏ'),
        ],
      ),
    );
    Future<void> one(int index, DateTime when, String title, String body) async {
      try {
        await plugin.zonedSchedule(
          _notificationId(task.id, index),
          title,
          body,
          tz.TZDateTime.from(when, tz.local),
          details,
          payload: task.id,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } catch (_) {
        await plugin.zonedSchedule(
          _notificationId(task.id, index),
          title,
          body,
          tz.TZDateTime.from(when, tz.local),
          details,
          payload: task.id,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    }

    await one(0, due, 'Echo · Đến giờ rồi', '${task.title}. Làm luôn nhé?');
    await one(1, due.add(const Duration(minutes: 10)),
        'Echo · Mình giục nhẹ nè', '${task.title} vẫn đang chờ cậu đó.');
  }

  Future<void> rescheduleAll() async {
    for (final task in await db.allTasks()) {
      if (task.status == 'pending') await schedule(task);
    }
  }

  Future<void> applyAction(Task task, String action) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (action == 'done' || action == 'skip') {
      await db.saveTask(TasksCompanion(
        id: Value(task.id),
        title: Value(task.title),
        dueAt: Value(task.dueAt),
        durationMinutes: Value(task.durationMinutes),
        recurrence: Value(task.recurrence),
        status: Value(action == 'done' ? 'done' : 'skipped'),
        originText: Value(task.originText),
        createdAt: Value(task.createdAt),
        updatedAt: Value(now),
      ));
      await cancel(task.id);
      if (task.recurrence != 'none') {
        var next = DateTime.fromMillisecondsSinceEpoch(task.dueAt);
        final days = task.recurrence == 'weekly' ? 7 : 1;
        do {
          next = next.add(Duration(days: days));
        } while (!next.isAfter(DateTime.now()));
        final nextId = const Uuid().v4();
        await db.saveTask(TasksCompanion(
          id: Value(nextId),
          title: Value(task.title),
          dueAt: Value(next.millisecondsSinceEpoch),
          durationMinutes: Value(task.durationMinutes),
          recurrence: Value(task.recurrence),
          status: const Value('pending'),
          originText: Value(task.originText),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
        final nextTask = await db.taskById(nextId);
        if (nextTask != null) await schedule(nextTask);
      }
    } else if (action == 'snooze') {
      final next = DateTime.now().add(const Duration(minutes: 15));
      await db.saveTask(TasksCompanion(
        id: Value(task.id),
        title: Value(task.title),
        dueAt: Value(next.millisecondsSinceEpoch),
        durationMinutes: Value(task.durationMinutes),
        recurrence: Value(task.recurrence),
        status: const Value('pending'),
        originText: Value(task.originText),
        createdAt: Value(task.createdAt),
        updatedAt: Value(now),
      ));
      final updated = await db.taskById(task.id);
      if (updated != null) await schedule(updated);
    }
  }
}
