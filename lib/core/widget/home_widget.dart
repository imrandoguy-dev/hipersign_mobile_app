import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../shared/models/models.dart';
import '../repository.dart';

const _channel = MethodChannel('hipersign/phone');

/// Sends today's follow-ups and meetings to the home screen widget (Android).
/// Pending work first, then what's done. Safe to call often; does nothing offline.
Future<void> updateHomeWidget(Repository repo) async {
  if (!Platform.isAndroid) return;
  try {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final d = await repo.calendar(day, day);
    final today = openFirst(d.items.where((a) =>
        a.start != null && a.start!.year == day.year && a.start!.month == day.month && a.start!.day == day.day));
    final items = [
      for (final a in today)
        {
          'time': DateFormat.jm().format(a.start!),
          'text': a.party != null && a.party!.name.isNotEmpty ? '${a.title} · ${a.party!.name}' : a.title,
          'done': !a.isOpen,
          'overdue': a.isOpen && a.start!.isBefore(now),
        },
    ];
    final earlier = d.overdue.where((a) => a.start != null && a.start!.isBefore(day)).length;
    await _channel.invokeMethod('updateWidget', {
      'json': jsonEncode({
        'date': DateFormat('yyyy-MM-dd').format(day),
        'label': DateFormat('EEE d MMM').format(day),
        'items': items,
        'open': today.where((a) => a.isOpen).length,
        'overdue_before': earlier,
        'updated': DateFormat.jm().format(now),
      }),
    });
  } catch (_) {
    // Offline or no widget support: the widget keeps its last copy.
  }
}

/// Asks the launcher to add the widget to the home screen. False when the phone can't.
Future<bool> pinHomeWidget() async {
  if (!Platform.isAndroid) return false;
  try {
    return await _channel.invokeMethod<bool>('pinWidget') ?? false;
  } catch (_) {
    return false;
  }
}
