import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hipersign_mobile_app/features/whatsapp/chats_screen.dart';
import 'package:hipersign_mobile_app/shared/models/whatsapp.dart';

void main() {
  test('chat and message JSON', () {
    final c = WaChat.fromJson({
      'phone': '+918078368600',
      'key': '918078368600',
      'title': 'AdzProHub',
      'party': {'kind': 'Lead', 'doctype': 'CRM Lead', 'id': 'CRM-LEAD-1', 'name': 'AdzProHub'},
      'unread': 2,
      'window_open': true,
      'last_message_at': '2026-10-15T12:03:43+05:30',
    });
    expect(c.inErp, isTrue);
    expect(c.partyKind, 'Lead');
    expect(c.unread, 2);
    expect(c.windowOpen, isTrue);

    final m = WaMessage.fromJson({
      'id': 'abc',
      'direction': 'in',
      'kind': 'audio',
      'media': {'kind': 'audio', 'ext': 'ogg', 'name': 'x.ogg'},
      'at': '2026-10-15T12:03:43+05:30',
    });
    expect(m.incoming, isTrue);
    expect(m.media!.ext, 'ogg');
  });

  test('template preview fills the values', () {
    final t = WaTemplate.fromJson({
      'id': 'meeting_confirmation-en_US',
      'title': 'Meeting confirmation',
      'body': 'Hello {{1}}, your meeting is on {{2}}.',
      'params': 2,
      'header_type': 'IMAGE',
    });
    expect(t.needsPicture, isTrue);
    expect(t.preview(['Ravi', '']), 'Hello Ravi, your meeting is on {{2}}.');
    expect(t.preview(['Ravi', 'Monday']), 'Hello Ravi, your meeting is on Monday.');
  });

  test('chat list times', () {
    final now = DateTime(2026, 10, 15, 18);
    expect(chatTime(DateTime(2026, 10, 14, 9), now: now), 'Yesterday');
    expect(chatTime(DateTime(2026, 10, 12, 9), now: now), 'Mon');
    expect(chatTime(DateTime(2026, 9, 1, 9), now: now), '1 Sep');
  });

  testWidgets('chat tile shows the unread count and "New number"', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatTile(
          chat: WaChat(phone: '+919800000000', key: '919800000000', title: '+919800000000', unread: 3, lastMessage: 'Hi'),
          onTap: () {},
        ),
      ),
    ));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('New number'), findsOneWidget);
    expect(find.text('Hi'), findsOneWidget);
  });
}
