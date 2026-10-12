import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../phone/direct_call.dart';
import '../repository.dart';

const _syncedKey = 'hm_callerid_synced_at';
const _askedKey = 'hm_callerid_asked';

/// Copies "phone number -> customer / lead / deal" from ERPNext to the phone, so the
/// caller pop-up can name callers instantly (even offline). Refreshed every 30 minutes.
Future<void> syncCallerDirectory(Repository repo, {bool force = false}) async {
  if (!Platform.isAndroid) return;
  final prefs = await SharedPreferences.getInstance();
  final last = DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_syncedKey) ?? 0);
  if (!force && DateTime.now().difference(last) < const Duration(minutes: 30)) return;
  final items = await repo.phoneDirectory();
  final map = <String, List<dynamic>>{
    for (final i in items) i['k'].toString(): [i['n'], i['t'], i['d'], i['i'], i['s']],
  };
  await saveCallerDirectory(jsonEncode(map));
  await prefs.setInt(_syncedKey, DateTime.now().millisecondsSinceEpoch);
}

/// Ask once for the phone / call-log permission the pop-up needs.
Future<void> askCallerIdOnce() async {
  if (!Platform.isAndroid) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_askedKey) == true) return;
  final status = await callerIdStatus();
  if (status == null || status.phone) return;
  await prefs.setBool(_askedKey, true);
  await requestCallerIdPermissions();
}
