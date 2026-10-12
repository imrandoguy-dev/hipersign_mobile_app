import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hipersign_mobile_app/app/theme.dart';
import 'package:hipersign_mobile_app/shared/models/models.dart';
import 'package:hipersign_mobile_app/shared/widgets/activity_card.dart';

void main() {
  testWidgets('activity card shows title, status label and contact buttons', (tester) async {
    final a = Activity.fromJson({
      'id': '1',
      'title': 'Site visit',
      'activity_type': 'Meeting',
      'status': 'Pending',
      'display_state': 'active',
      'priority': 'Medium',
      'start': '2026-10-13T10:30:00+05:30',
      'party': {
        'kind': 'Customer',
        'doctype': 'Customer',
        'id': 'ABC',
        'name': 'ABC University',
        'phones': [],
        'primary_phone': {'raw': '9876543210', 'e164': '+919876543210', 'valid': true, 'tel_url': 'tel:+919876543210', 'whatsapp_url': 'https://wa.me/919876543210'},
      },
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: ActivityCard(activity: a, onTap: () {})),
    ));
    expect(find.text('Site visit'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('ABC University'), findsOneWidget);
    expect(find.byTooltip('Call'), findsOneWidget);
    expect(find.byTooltip('WhatsApp'), findsOneWidget);
  });
}
