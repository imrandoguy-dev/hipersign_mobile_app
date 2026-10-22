import 'package:flutter_test/flutter_test.dart';
import 'package:hipersign_mobile_app/shared/models/development.dart';
import 'package:hipersign_mobile_app/shared/models/sales.dart';
import 'package:hipersign_mobile_app/shared/models/team.dart';

void main() {
  test('call target progress', () {
    final p = TargetProgress.fromJson({
      'target': 70, 'made': 40, 'connected': 22, 'counted': 40, 'remaining': 30, 'reached': false,
      'check_times': ['16:00', '17:00'], 'idle_minutes': 30, 'working_day': true,
    })!;
    expect(p.remaining, 30);
    expect(p.checkTimes, ['16:00', '17:00']);
    expect(TargetProgress.fromJson(null), isNull);
  });

  test('daily report items split done / not done', () {
    final r = DailyReport.fromJson({
      'user': 'a@b.c', 'name': 'Revathi', 'date': '2026-10-22', 'done': 1, 'not_done': 1, 'calls_made': 36,
      'calls_connected': 20, 'call_target': 70,
      'items': [
        {'kind': 'Follow-up', 'title': 'Call Ravi', 'result': 'Done', 'done': true, 'open': false},
        {'kind': 'Accounts', 'title': 'Pay GST', 'result': 'Not done', 'done': false, 'open': true, 'reference_doctype': 'Team Task', 'reference_name': 'TASK-2026-00001'},
      ],
    });
    expect(r.items.where((i) => i.open).single.refName, 'TASK-2026-00001');
    expect(r.callTarget, 70);
  });

  test('attachments and team tasks', () {
    final a = Attachment.fromJson({'id': 'x1', 'name': 'Voice note 22 Oct.m4a', 'kind': 'audio', 'size': 2048});
    expect(a.ext, 'm4a');
    final t = DevTask.fromJson({'id': 'TASK-1', 'kind': 'team', 'team': 'Hiring', 'title': 'Post job ad', 'attachments': 2});
    expect((t.kind, t.team, t.attachments), ('team', 'Hiring', 2));
  });

  test('customer stage', () {
    final j = Journey.fromJson({
      'stage': {'key': 'training', 'label': 'In training', 'state': 'active', 'detail': 'Day 2 of 5 · with Megha'},
      'steps': [
        {'key': 'lead', 'label': 'Lead', 'state': 'done'},
        {'key': 'training', 'label': 'Training', 'state': 'active'},
      ],
      'quotations': [
        {'id': 'SAL-QTN-1', 'status': 'Open', 'date': '2026-10-22', 'total_text': '₹ 15,000.00'},
      ],
    })!;
    expect(j.stage!.label, 'In training');
    expect(j.quotations.single.id, 'SAL-QTN-1');
    expect(Journey.fromJson(null), isNull);
  });
}
