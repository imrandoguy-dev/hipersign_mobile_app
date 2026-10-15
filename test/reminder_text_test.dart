import 'package:flutter_test/flutter_test.dart';
import 'package:hipersign_mobile_app/core/notifications/notification_service.dart';
import 'package:hipersign_mobile_app/shared/models/models.dart';

void main() {
  test('phone reminder shows customer, title, time and notes', () {
    final a = Activity.fromJson({
      'id': '7',
      'title': 'Discuss AMC renewal',
      'activity_type': 'Follow-up',
      'status': 'Pending',
      'priority': 'High',
      'start': '2026-10-16T10:30:00',
      'description': '<p>Bring the new price list</p>',
      'party': {'kind': 'Customer', 'doctype': 'Customer', 'id': 'C1', 'name': 'Amal Traders'},
    });
    final (title, body) = NotificationService.reminderText(a, 15);
    expect(title, 'Upcoming follow-up in 15 min · Amal Traders');
    expect(body, contains('Discuss AMC renewal'));
    expect(body, contains('10:30'));
    expect(body, contains('Notes: Bring the new price list'));
  });
}
