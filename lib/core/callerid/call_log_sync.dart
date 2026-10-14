import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../phone/direct_call.dart';
import '../recordings/recording_service.dart';
import '../repository.dart';

String _last9(String s) {
  final d = s.replaceAll(RegExp(r'[^0-9]'), '');
  return d.length > 9 ? d.substring(d.length - 9) : d;
}

/// Uploads work calls from the phone's call history for the Calling Activity report:
/// calls to ERPNext customers / leads / deals, and calls started from Hipersign.
/// Personal calls (unknown numbers dialled outside Hipersign) are never sent.
Future<void> syncCallLog(Repository repo, String user, {bool force = false}) async {
  if (!Platform.isAndroid) return;
  final prefs = await SharedPreferences.getInstance();
  final sinceKey = 'hm_calllog_since:$user';
  final atKey = 'hm_calllog_at:$user';
  final lastRun = DateTime.fromMillisecondsSinceEpoch(prefs.getInt(atKey) ?? 0);
  if (!force && DateTime.now().difference(lastRun) < const Duration(minutes: 2)) return;
  await prefs.setInt(atKey, DateTime.now().millisecondsSinceEpoch);

  // First run: the last 3 days. Later: from the last upload, but always re-check the last
  // 24 hours so calls skipped while their number was still unknown get sent once known.
  final firstRun = prefs.getInt(sinceKey) == null;
  final lastSent = DateTime.fromMillisecondsSinceEpoch(
      prefs.getInt(sinceKey) ?? DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch);
  final dayAgo = DateTime.now().subtract(const Duration(hours: 24));
  final since = firstRun || lastSent.isBefore(dayAgo) ? lastSent : dayAgo;
  final sentKey = 'hm_calllog_sent:$user';
  final sent = (prefs.getStringList(sentKey) ?? const <String>[]).toSet();
  final rows = await readPhoneCallLog(since);
  if (rows == null || rows.isEmpty) return; // no call-log access, or nothing new

  final appCalls = RecordingService.instance.entries;
  // Numbers already linked on this phone (e.g. a lead created minutes ago from Google).
  final known = <String, List<String>>{
    for (final e in appCalls)
      if (e.party != null && e.partyDoctype != null) _last9(e.number): [e.partyDoctype!, e.party!],
  };
  final items = <Map<String, dynamic>>[];
  var newest = lastSent.millisecondsSinceEpoch;
  for (final r in rows) {
    final date = (r['date'] as num).toInt();
    final key = '${r['id']}-$date';
    if (sent.contains(key)) continue;
    if (!isWorkSimRow(r)) continue; // a personal SIM (Settings > Work SIM)
    final direction = switch ((r['type'] as num?)?.toInt()) {
      2 => 'outgoing',
      1 || 7 => 'incoming',
      3 || 5 => 'missed',
      _ => null,
    };
    if (direction == null) continue;
    final number = r['number']?.toString() ?? '';
    final at = DateTime.fromMillisecondsSinceEpoch(date);
    // Was this call started from Hipersign? (same number, within 2 minutes)
    final fromApp = direction == 'outgoing'
        ? appCalls
            .where((e) => _last9(e.number) == _last9(number) && e.startedAt.difference(at).inSeconds.abs() < 120)
            .firstOrNull
        : null;
    final party = r['party'] is List ? (r['party'] as List).map((e) => e.toString()).toList() : known[_last9(number)];
    if (party == null && fromApp == null) continue; // personal (or not known yet: retried later)
    if (date > newest) newest = date;
    items.add({
      'key': key,
      'number': number,
      'started_at': at.toUtc().toIso8601String(),
      'duration': (r['duration'] as num?)?.toInt() ?? 0,
      'direction': direction,
      'via_app': fromApp != null,
      'party_doctype': fromApp?.partyDoctype ?? party?[0],
      'party': fromApp?.party ?? party?[1],
      'activity': fromApp?.activity,
    });
  }
  for (var i = 0; i < items.length; i += 200) {
    final batch = items.sublist(i, i + 200 > items.length ? items.length : i + 200);
    await repo.syncCalls(batch);
    sent.addAll(batch.map((b) => b['key'] as String));
  }
  final keep = sent.length > 600 ? sent.skip(sent.length - 600) : sent;
  await prefs.setStringList(sentKey, keep.toList());
  await prefs.setInt(sinceKey, newest);
}
