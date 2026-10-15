import 'package:flutter_test/flutter_test.dart';
import 'package:hipersign_mobile_app/shared/models/models.dart';

Activity _a(String id, String status, String start) => Activity.fromJson({
      'id': id,
      'title': 'T$id',
      'activity_type': 'Follow-up',
      'status': status,
      'display_state': status == 'Completed' ? 'completed' : 'pending',
      'start': start,
    });

void main() {
  test('pending first in time order, completed / cancelled at the bottom', () {
    final list = openFirst([
      _a('1', 'Completed', '2026-10-15T09:00:00+05:30'),
      _a('2', 'Pending', '2026-10-15T15:00:00+05:30'),
      _a('3', 'Cancelled', '2026-10-15T08:00:00+05:30'),
      _a('4', 'Pending', '2026-10-15T11:00:00+05:30'),
    ]);
    expect(list.map((a) => a.id).toList(), ['4', '2', '3', '1']);
  });
}
