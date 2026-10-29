import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../shared/models/development.dart';
import '../../shared/models/models.dart';
import '../repository.dart';

const _channel = MethodChannel('hipersign/phone');

/// Sends the coming days' follow-ups and meetings to the home screen widget (Android):
/// today first (pending before done), then the next days that have work - like an agenda.
/// Safe to call often; does nothing offline.
Future<void> updateHomeWidget(Repository repo) async {
  if (!Platform.isAndroid) return;
  try {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final last = day.add(const Duration(days: widgetDays - 1));
    final d = await repo.calendar(day, last);
    final days = <Map<String, dynamic>>[];
    for (var i = 0; i < widgetDays; i++) {
      final date = day.add(Duration(days: i));
      final work = openFirst(d.items.where((a) =>
          a.start != null && a.start!.year == date.year && a.start!.month == date.month && a.start!.day == date.day));
      // Open tasks: today (until done) and on their deadline day; not repeated on every day.
      // Tasks: open ones once, under today (with their due date), until done; finished ones
      // only on their deadline day.
      bool sameDay(DateTime x) => x.year == date.year && x.month == date.month && x.day == date.day;
      final dayTasks = d.tasks.where((t) {
        final dl = t.deadline;
        if (dl == null) return false;
        if (t.isOpen) return i == 0 && taskOnDay(t, date);
        return sameDay(dl);
      }).toList();
      if (work.isEmpty && dayTasks.isEmpty && i > 0) continue; // only today is listed when empty
      days.add({
        'date': DateFormat('yyyy-MM-dd').format(date),
        'label': DateFormat('EEE, d MMM').format(date),
        'items': [
          for (final a in work)
            {
              'time': DateFormat.jm().format(a.start!),
              'text': a.party != null && a.party!.name.isNotEmpty ? '${a.title} · ${a.party!.name}' : a.title,
              'done': !a.isOpen,
              'overdue': a.isOpen && a.start!.isBefore(now),
            },
          for (final t in dayTasks) _taskRow(t, date, now),
        ],
      });
    }
    // Open work from earlier days stays on the widget (newest first) until it is done.
    Map<String, dynamic>? target;
    try {
      final t = await repo.myTarget();
      if (t != null && t.workingDay && (t.target > 0 || t.meetingTarget > 0)) {
        target = {
          'idle': t.idle,
          'idle_title': 'No calls for ${t.idleFor ?? 'a while'}',
          'line': '${t.remaining} more ${t.unit} needed (${t.counted} of ${t.target})',
          'short': t.target > 0 ? '${t.counted}/${t.target} calls' : '${t.meetings}/${t.meetingTarget} meetings',
        };
      }
    } catch (_) {}
    final earlier = d.overdue.where((a) => a.isOpen && a.start != null && a.start!.isBefore(day)).toList()
      ..sort((a, b) => b.start!.compareTo(a.start!));
    await _channel.invokeMethod('updateWidget', {
      'json': jsonEncode({
        'date': DateFormat('yyyy-MM-dd').format(day),
        'days': days,
        'open_today': days.isEmpty ? 0 : (days.first['items'] as List).where((x) => x['done'] != true).length,
        'overdue_before': earlier.length,
        'overdue': [
          for (final a in earlier)
            {
              'time': DateFormat('d MMM').format(a.start!),
              'text': a.party != null && a.party!.name.isNotEmpty ? '${a.title} · ${a.party!.name}' : a.title,
            },
          for (final t in d.tasksOverdue.where((t) => t.deadline != null && t.deadline!.isBefore(day)))
            {'time': DateFormat('d MMM').format(t.deadline!), 'text': 'Task: ${t.title}'},
        ],
        'updated': DateFormat.jm().format(now),
        'updated_ms': now.millisecondsSinceEpoch,
        if (target != null) 'target': target,
      }),
    });
  } catch (_) {
    // Offline or no widget support: the widget keeps its last copy.
  }
}

/// A task row: the time when it is due that day ("" for a date-only deadline), otherwise
/// its due date in the text, so an open task is not mistaken for something at that time today.
Map<String, dynamic> _taskRow(DevTask t, DateTime date, DateTime now) {
  final dl = t.deadline!;
  final dueToday = dl.year == date.year && dl.month == date.month && dl.day == date.day;
  final midnight = dl.hour == 0 && dl.minute == 0;
  return {
    'time': dueToday && !midnight ? DateFormat.jm().format(dl) : '',
    'text': dueToday || !t.isOpen ? 'Task: ${t.title}' : 'Task: ${t.title} · due ${DateFormat('EEE d MMM').format(dl)}',
    'done': !t.isOpen,
    'overdue': t.isOpen && dl.isBefore(now),
  };
}

/// How far ahead the widget looks.
const widgetDays = 14;

/// Asks the launcher to add the widget to the home screen. False when the phone can't.
Future<bool> pinHomeWidget() async {
  if (!Platform.isAndroid) return false;
  try {
    return await _channel.invokeMethod<bool>('pinWidget') ?? false;
  } catch (_) {
    return false;
  }
}

