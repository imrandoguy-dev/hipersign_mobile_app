import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../app/nav.dart';
import '../../shared/models/models.dart';
import '../api/api_client.dart';
import '../cache/cache_store.dart';
import '../widget/home_widget.dart';
import 'alarm.dart';
import 'firebase_options.dart';

const appVersion = '0.1.0';
// Reminders ring and vibrate. (A new id: Android keeps an old channel's settings forever.)
const _channelId = 'hipersign_reminders';
const _oldChannelId = 'hipersign_alerts';
const _localIdsPref = 'local_reminder_ids';

/// Push (FCM / APNs via Firebase) + local reminders.
///
/// - Server pushes: assignment, reschedule, reminder, trial updates. Payloads are
///   generic; `data.route` tells the app what to open.
/// - Local reminders: backup for recently synced schedules (used when push is
///   not available on this phone, or when the user turns them on).
/// Every step tolerates missing permissions / missing Firebase config without crashing.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool firebaseReady = false;
  String? pushToken;
  String? pendingRoute;
  void Function(String route)? onOpenRoute;
  StreamSubscription<String>? _tokenSub;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _local.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Hipersign alerts',
      channelDescription: 'Assignments, reminders and trial updates',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBadge: true),
  );

  /// Same channel, but the whole multi-line text (customer, notes...) shows when expanded.
  static NotificationDetails _expandable(String body) => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Hipersign alerts',
          channelDescription: 'Assignments, reminders and trial updates',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          category: AndroidNotificationCategory.reminder,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBadge: true),
      );

  /// 15 -> "in 15 min", 60 -> "in 1 h", 1440 -> "tomorrow" (same wording as the server).
  static String beforeLabel(int m) {
    if (m % 1440 == 0) return m == 1440 ? 'tomorrow' : 'in ${m ~/ 1440} days';
    if (m >= 60 && m % 60 == 0) return 'in ${m ~/ 60} h';
    return 'in $m min';
  }

  /// Rings the High priority alarm once now, so people can hear what it sounds like.
  Future<void> testAlarm() => showAlarmFromData(_local, {
        'notification_id': 'test',
        'title': 'Test alarm · High priority follow-up',
        'body': 'This is how High priority reminders ring. Tap or swipe to stop.',
      });

  /// Text of a phone-side reminder: who, what, when and the notes (like the server push).
  static (String, String) reminderText(Activity a, int minutesBefore) {
    final kind = a.activityType.toLowerCase();
    final who = a.party?.name;
    final head = minutesBefore > 0
        ? 'Upcoming $kind ${beforeLabel(minutesBefore)}'
        : '${kind[0].toUpperCase()}${kind.substring(1)} now';
    final title = who == null || who.isEmpty ? head : '$head · $who';
    String clip(String t, int n) {
      final s = t.replaceAll(RegExp(r'\s+'), ' ').trim();
      return s.length > n ? '${s.substring(0, n - 1)}…' : s;
    }

    final lines = <String>[
      '${DateFormat('d MMM, h:mm a').format(a.start!)} · ${clip(a.title, 120)}',
      if ((a.location ?? '').trim().isNotEmpty) 'Place: ${clip(a.location!, 100)}',
      if ((a.description ?? '').trim().isNotEmpty && a.description!.trim() != a.title.trim())
        'Notes: ${clip(a.description!.replaceAll(RegExp(r'<[^>]+>'), ' '), 300)}',
    ];
    return (title, lines.join('\n'));
  }

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) => _open(r.payload),
      );
      await _android?.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        'Hipersign alerts',
        description: 'Reminders, assignments and trial updates',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ));
      await _android?.createNotificationChannel(alarmChannel());
      try {
        await _android?.deleteNotificationChannel(channelId: _oldChannelId);
      } catch (_) {}
      final launch = await _local.getNotificationAppLaunchDetails();
      final launchPayload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && isDeepLink(launchPayload)) {
        pendingRoute = launchPayload;
      }
    } catch (_) {
      // Local notifications unavailable: the app still works.
    }

    try {
      await Firebase.initializeApp(options: hipersignFirebaseOptions);
      firebaseReady = true;
    } catch (_) {
      firebaseReady = false; // google-services.json / GoogleService-Info.plist not configured
    }
    if (firebaseReady) {
      FirebaseMessaging.onBackgroundMessage(hipersignBackgroundMessage); // alarm pushes while closed
      final fm = FirebaseMessaging.instance;
      await fm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data['route']?.toString()));
      try {
        final initial = await fm.getInitialMessage();
        final route = initial?.data['route']?.toString();
        if (isDeepLink(route)) pendingRoute = route;
      } catch (_) {}
    }
  }

  void _onForegroundMessage(RemoteMessage m) {
    // iOS shows foreground pushes itself (presentation options above).
    if (!Platform.isAndroid) return;
    if (m.data['alarm'] == '1') {
      showAlarmFromData(_local, Map<String, dynamic>.from(m.data));
      widgetAlertFromPush(Map<String, dynamic>.from(m.data));
      return;
    }
    final n = m.notification;
    if (n == null) return;
    _local.show(
      id: DateTime.now().millisecondsSinceEpoch & 0x3fffffff,
      title: n.title,
      body: n.body,
      notificationDetails: n.body == null ? _details : _expandable(n.body!),
      payload: m.data['route']?.toString(),
    );
  }

  void _open(String? route) {
    if (!isDeepLink(route)) return;
    if (onOpenRoute != null) {
      onOpenRoute!(route!);
    } else {
      pendingRoute = route;
    }
  }

  String? takePendingRoute() {
    final r = pendingRoute;
    pendingRoute = null;
    return r;
  }

  // ------------------------------------------------------------ permissions

  Future<bool> requestPermission() async {
    try {
      if (Platform.isAndroid) {
        return await _android?.requestNotificationsPermission() ?? true;
      }
      if (firebaseReady) {
        final s = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
        return s.authorizationStatus == AuthorizationStatus.authorized ||
            s.authorizationStatus == AuthorizationStatus.provisional;
      }
      return await _ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// null = unknown
  Future<bool?> permissionGranted() async {
    try {
      if (Platform.isAndroid) return await _android?.areNotificationsEnabled();
      final p = await _ios?.checkPermissions();
      return p?.isEnabled;
    } catch (_) {
      return null;
    }
  }

  Future<bool> canScheduleExact() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestExactAlarms() async {
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  // ------------------------------------------------------------ device registration

  bool get pushAvailable => firebaseReady && pushToken != null;

  Future<void> registerDevice(ApiClient api, String deviceId) async {
    String? token;
    if (firebaseReady) {
      try {
        if (Platform.isIOS) await FirebaseMessaging.instance.getAPNSToken();
        token = await FirebaseMessaging.instance.getToken();
      } catch (_) {
        token = null; // e.g. iOS simulator / APNs not ready yet
      }
    }
    pushToken = token;
    await api.post('devices.register_device', {
      'device_id': deviceId,
      'platform': Platform.isIOS ? 'iOS' : 'Android',
      'push_token': token,
      'app_version': appVersion,
      'device_name': Platform.isIOS ? 'iPhone' : 'Android phone',
    });
    await _tokenSub?.cancel();
    if (firebaseReady) {
      _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        pushToken = t;
        try {
          await api.post('devices.register_device', {
            'device_id': deviceId,
            'platform': Platform.isIOS ? 'iOS' : 'Android',
            'push_token': t,
            'app_version': appVersion,
          });
        } catch (_) {}
      });
    }
  }

  Future<void> onSignedOut() async {
    await _tokenSub?.cancel();
    _tokenSub = null;
    await cancelLocalReminders();
    if (firebaseReady) {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
    pushToken = null;
  }

  // ------------------------------------------------------------ local reminders

  int _idFor(String activityId) => 100000 + ((int.tryParse(activityId) ?? activityId.hashCode) & 0x07ffffff);

  Future<void> cancelLocalReminders() async {
    final store = await CacheStore.instance();
    final ids = (store.getPref(_localIdsPref) ?? '').split(',').where((s) => s.isNotEmpty);
    for (final id in ids) {
      try {
        await _local.cancel(id: int.parse(id));
      } catch (_) {}
    }
    await store.setPref(_localIdsPref, null);
  }

  /// Re-plans phone-side reminders from the latest synced schedule. Called after
  /// each calendar sync, so rescheduled / completed work never fires a stale alert.
  Future<void> syncLocalReminders(
    List<Activity> activities, {
    required List<int> offsets,
    required bool enabled,
    bool alarmHighPriority = true,
  }) async {
    await cancelLocalReminders();
    if (!enabled) return;
    final now = DateTime.now();
    final upcoming = activities
        .where((a) => a.isOpen && a.start != null && a.start!.isAfter(now))
        .toList()
      ..sort((a, b) => a.start!.compareTo(b.start!));
    final exact = await canScheduleExact();
    final ids = <int>[];
    for (final a in upcoming.take(30)) {
      final own = a.reminderOffsets;
      final times = (own != null && own.isNotEmpty) ? own : offsets;
      final alarm = alarmHighPriority && (a.priority == 'High' || a.priority == 'Urgent');
      for (final (i, offset) in times.take(5).indexed) {
        final at = a.start!.subtract(Duration(minutes: offset));
        if (!at.isAfter(now.add(const Duration(seconds: 30)))) continue;
        final id = _idFor(a.id) + i * 0x08000000;
        try {
          final (title, body) = reminderText(a, offset);
          await _local.zonedSchedule(
            id: id,
            title: title,
            body: body,
            scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
            notificationDetails: alarm ? alarmDetails(body) : _expandable(body),
            androidScheduleMode: alarm
                ? AndroidScheduleMode.alarmClock
                : (exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle),
            payload: '/activity/${a.id}',
          );
          ids.add(id);
        } catch (_) {
          // Permission denied or OS limit reached: skip quietly; server push still applies.
        }
      }
    }
    final store = await CacheStore.instance();
    await store.setPref(_localIdsPref, ids.join(','));
  }
}
