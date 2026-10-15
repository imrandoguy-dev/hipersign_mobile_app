import 'dart:typed_data';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// "Rings like an alarm": alarm sound on the alarm volume, long vibration, and it keeps
/// ringing until it is opened or swiped away (Android's "insistent" flag) - used for the
/// reminders of High priority follow-ups and meetings.
const alarmChannelId = 'hipersign_alarms';
const _alarmSound = UriAndroidNotificationSound('content://settings/system/alarm_alert');
final _alarmVibration = Int64List.fromList([0, 900, 500, 900, 500, 900, 500, 900]);
const _flagInsistent = 4; // Notification.FLAG_INSISTENT: repeat sound until dismissed

AndroidNotificationChannel alarmChannel() => AndroidNotificationChannel(
      alarmChannelId,
      'High priority alarms',
      description: 'Reminders of High priority follow-ups and meetings ring like an alarm',
      importance: Importance.max,
      playSound: true,
      sound: _alarmSound,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      vibrationPattern: _alarmVibration,
    );

NotificationDetails alarmDetails(String body) => NotificationDetails(
      android: AndroidNotificationDetails(
        alarmChannelId,
        'High priority alarms',
        channelDescription: 'Reminders of High priority follow-ups and meetings ring like an alarm',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        playSound: true,
        sound: _alarmSound,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
        vibrationPattern: _alarmVibration,
        additionalFlags: Int32List.fromList(const [_flagInsistent]),
        timeoutAfter: 10 * 60 * 1000, // stop ringing after 10 minutes if nobody reacts
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

int alarmNotificationId(Map<String, dynamic> data) =>
    0x30000000 + ((data['notification_id']?.toString() ?? DateTime.now().toString()).hashCode & 0x0fffffff);

/// Shows an alarm push (a data-only message from the server: title, body, route).
Future<void> showAlarmFromData(FlutterLocalNotificationsPlugin plugin, Map<String, dynamic> data) async {
  final title = data['title']?.toString() ?? 'Hipersign reminder';
  final body = data['body']?.toString() ?? '';
  await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(alarmChannel());
  await plugin.show(
    id: alarmNotificationId(data),
    title: title,
    body: body,
    notificationDetails: alarmDetails(body),
    payload: data['route']?.toString(),
  );
}

/// Runs when an alarm push arrives while Hipersign is closed or in the background.
@pragma('vm:entry-point')
Future<void> hipersignBackgroundMessage(RemoteMessage message) async {
  if (message.data['alarm'] != '1') return; // normal pushes are shown by Android itself
  WidgetsFlutterBinding.ensureInitialized();
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
  );
  await showAlarmFromData(plugin, Map<String, dynamic>.from(message.data));
}
