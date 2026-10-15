import 'package:flutter_test/flutter_test.dart';
import 'package:hipersign_mobile_app/features/calls/calls_screen.dart';
import 'package:hipersign_mobile_app/shared/models/calls.dart';

void main() {
  test('call list JSON', () {
    final p = CallsPage.fromJson({
      'items': [
        {
          'id': 'c1',
          'direction': 'Outgoing',
          'connected': true,
          'duration': 75,
          'phone': '+919895055001',
          'call_type': 'Follow-up',
          'party': {'kind': 'Lead', 'doctype': 'CRM Lead', 'id': 'CRM-LEAD-1', 'name': 'AS Square'},
          'recording': {'id': 'REC-1', 'ext': 'm4a'},
          'at': '2026-10-15T15:40:00+05:30',
        },
        {'id': 'c2', 'direction': 'Missed', 'connected': false, 'duration': 0, 'phone': '+919800000000'},
      ],
      'next_cursor': '40',
      'today': {'total': 12, 'connected': 7, 'talk': 3725},
    });
    expect(p.items.first.title, 'AS Square');
    expect(p.items.first.party!.doctype, 'CRM Lead');
    expect(p.items.first.recordingId, 'REC-1');
    expect(p.items.last.title, '+919800000000');
    expect(p.items.last.party, isNull);
    expect(p.today!['total'], 12);
    expect(p.nextCursor, '40');
  });

  test('talk time', () {
    expect(talkTime(45), '45 s');
    expect(talkTime(240), '4 min');
    expect(talkTime(3725), '1 h 02 min');
  });
}
