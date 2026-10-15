import 'package:flutter_test/flutter_test.dart';
import 'package:hipersign_mobile_app/shared/models/models.dart';

TrialPeriod _t(Map<String, dynamic> m) => TrialPeriod.fromJson({
      'series': 'TB-1',
      'days': 7,
      'start_date': '2026-10-19',
      'end_date': '2026-10-25',
      'sessions': [
        {'id': 'TB-1', 'status': 'Completed', 'session_no': 1, 'start': '2026-10-19T10:30:00+05:30'},
        {'id': 'TB-2', 'status': 'Booked', 'session_no': 2, 'start': '2026-10-20T10:30:00+05:30'},
      ],
      'sessions_done': 1,
      ...m,
    });

void main() {
  test('trial countdown wording', () {
    expect(_t({'phase': 'running', 'day_no': 3, 'days_left': 4}).countdown, 'Day 3 of 7 · 4 days left');
    expect(_t({'phase': 'running', 'day_no': 7, 'days_left': 0}).countdown, 'Day 7 of 7 · last day today');
    expect(_t({'phase': 'upcoming', 'starts_in': 1}).countdown, 'Starts tomorrow · 7-day trial');
    expect(_t({'phase': 'upcoming', 'starts_in': 4}).countdown, 'Starts in 4 days · 7-day trial');
    expect(_t({'phase': 'ended'}).countdown, 'Trial ended · 7 days');
    expect(_t({'phase': 'running'}).sessions.length, 2);
    expect(_t({'phase': 'running', 'day_no': 5, 'days_left': 2, 'today_off': true}).countdown,
        'Paused today (Sunday / holiday) · 2 days left');
  });
}
