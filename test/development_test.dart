import 'package:flutter_test/flutter_test.dart';
import 'package:hipersign_mobile_app/features/development/development_screen.dart';
import 'package:hipersign_mobile_app/shared/models/development.dart';

void main() {
  test('development task JSON and deadline text', () {
    final now = DateTime(2026, 10, 16, 10);
    final t = DevTask.fromJson({
      'id': 'DEV-2026-00001',
      'title': 'GST report',
      'status': 'In Progress',
      'priority': 'High',
      'developer': 'dev@x.com',
      'developer_name': 'Anu',
      'deadline': DateTime(2026, 10, 18, 18).toIso8601String(),
      'reminders': [1440, 60],
      'notes': [
        {'text': 'Started', 'by': 'Anu', 'at': '2026-10-16T09:00:00+05:30'},
      ],
    });
    expect(t.isOpen, isTrue);
    expect(t.reminders, [1440, 60]);
    expect(t.notes.single.text, 'Started');
    expect(deadlineText(t, now: now), startsWith('Due '));
    expect(deadlineText(t, now: now), endsWith('(in 2 days)'));

    final late = DevTask.fromJson({
      'id': 'x', 'title': 'y', 'status': 'Open', 'priority': 'Low', 'developer': 'd', 'developer_name': 'D',
      'deadline': '2026-10-14T18:00:00+05:30', 'late': true, 'late_text': '2 days late',
    });
    expect(deadlineText(late, now: now), startsWith('2 days late'));
  });
}
