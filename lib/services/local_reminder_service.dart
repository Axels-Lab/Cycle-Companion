import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class ReminderPreferences {
  const ReminderPreferences({
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  final bool enabled;
  final int hour;
  final int minute;
}

class LocalReminderService {
  static const _notificationId = 8246;
  static const _enabledKey = 'daily_reminder_enabled';
  static const _hourKey = 'daily_reminder_hour';
  static const _minuteKey = 'daily_reminder_minute';
  static const _defaultHour = 20;
  static const _defaultMinute = 0;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (!isSupported) {
      throw UnsupportedError('Local reminders are available on Android only.');
    }

    tz_data.initializeTimeZones();
    final timezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezone.identifier));
    final initialized = await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    if (initialized != true) {
      throw StateError('Could not initialize local notifications.');
    }
  }

  Future<ReminderPreferences> readPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    return ReminderPreferences(
      enabled: preferences.getBool(_enabledKey) ?? false,
      hour: preferences.getInt(_hourKey) ?? _defaultHour,
      minute: preferences.getInt(_minuteKey) ?? _defaultMinute,
    );
  }

  Future<void> saveTime(int hour, int minute) async {
    final preferences = await SharedPreferences.getInstance();
    final savedHour = await preferences.setInt(_hourKey, hour);
    final savedMinute = await preferences.setInt(_minuteKey, minute);
    if (!savedHour || !savedMinute) {
      throw StateError('Could not save your reminder time on this device.');
    }
  }

  Future<bool> enableAt(int hour, int minute) async {
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) {
      throw StateError('Android notifications are unavailable.');
    }
    final granted = await android.requestNotificationsPermission();
    if (granted != true) return false;

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduledDate.isAfter(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _notifications.zonedSchedule(
      id: _notificationId,
      title: 'A gentle check-in',
      body: 'Take a moment to add today’s cycle and mood entry.',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_check_in',
          'Daily check-in reminders',
          channelDescription: 'A private reminder to log your daily check-in.',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    final preferences = await SharedPreferences.getInstance();
    final savedEnabled = await preferences.setBool(_enabledKey, true);
    final savedHour = await preferences.setInt(_hourKey, hour);
    final savedMinute = await preferences.setInt(_minuteKey, minute);
    if (!savedEnabled || !savedHour || !savedMinute) {
      await _notifications.cancel(id: _notificationId);
      throw StateError('Could not save reminder settings on this device.');
    }
    return true;
  }

  Future<void> disable() async {
    await _notifications.cancel(id: _notificationId);
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setBool(_enabledKey, false);
    if (!saved) {
      throw StateError('Could not save reminder settings on this device.');
    }
  }
}
