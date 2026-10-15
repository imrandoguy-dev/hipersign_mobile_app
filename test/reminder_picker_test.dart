import 'package:flutter_test/flutter_test.dart';
import 'package:hipersign_mobile_app/core/notifications/notification_service.dart';
import 'package:hipersign_mobile_app/core/notifications/reminder_planner.dart';
import 'package:hipersign_mobile_app/shared/widgets/reminder_picker.dart';

void main() {
  test('reminder wording', () {
    expect(describeReminders([0, 15, 60]), '1 h before, 15 min before, at start time');
    expect(reminderLabel(1440), '1 day before');
    expect(NotificationService.beforeLabel(1440), 'tomorrow');
    expect(NotificationService.beforeLabel(120), 'in 2 h');
    expect(parseOffsets('60, 15,0'), [60, 15, 0]);
  });
}
