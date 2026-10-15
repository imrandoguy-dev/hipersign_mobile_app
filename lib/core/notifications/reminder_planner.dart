import '../repository.dart';
import 'notification_service.dart';

const phoneRemindersPref = 'phone_reminders'; // auto | on | off
const reminderMinutesPref = 'reminder_minutes';
const reminderOffsetsPref = 'reminder_offsets'; // e.g. "15,0"
const alarmHighPref = 'alarm_high_priority'; // "1" | "0"

/// "60,15,0" -> [60, 15, 0]
List<int> parseOffsets(String? v) =>
    (v ?? '').split(',').map((e) => int.tryParse(e.trim())).whereType<int>().toList();

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Plans phone-side backup reminders for the next two weeks.
/// "auto": only when server push is not available on this phone, so people
/// don't get every reminder twice.
Future<void> planLocalReminders(Repository repo) async {
  final mode = repo.cache.getPref(phoneRemindersPref) ?? 'auto';
  final minutes = int.tryParse(repo.cache.getPref(reminderMinutesPref) ?? '') ?? 15;
  var offsets = parseOffsets(repo.cache.getPref(reminderOffsetsPref));
  if (offsets.isEmpty) offsets = {minutes, 0}.toList();
  final alarm = repo.cache.getPref(alarmHighPref) != '0';
  final service = NotificationService.instance;
  final enabled = mode == 'on' || (mode == 'auto' && !service.pushAvailable);
  if (!enabled) {
    await service.cancelLocalReminders();
    return;
  }
  final today = _dateOnly(DateTime.now());
  try {
    final data = await repo.calendar(today, today.add(const Duration(days: 13)));
    await service.syncLocalReminders(data.items, offsets: offsets, enabled: true, alarmHighPriority: alarm);
  } catch (_) {
    // Keep previously scheduled reminders when offline.
  }
}
