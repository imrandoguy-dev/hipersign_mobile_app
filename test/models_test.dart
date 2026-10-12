import 'package:flutter_test/flutter_test.dart';
import 'package:hipersign_mobile_app/app/theme.dart';
import 'package:hipersign_mobile_app/core/api/api_client.dart';
import 'package:hipersign_mobile_app/core/repository.dart';
import 'package:hipersign_mobile_app/shared/models/models.dart';

void main() {
  test('activity parses the server payload', () {
    final a = Activity.fromJson({
      'id': '27',
      'title': 'Follow up on ERP demo',
      'activity_type': 'Follow-up',
      'status': 'Rescheduled',
      'display_state': 'rescheduled',
      'priority': 'High',
      'start': '2026-10-13T10:30:00+05:30',
      'end': '2026-10-13T10:45:00+05:30',
      'reschedule_count': 1,
      'party': {
        'kind': 'Lead',
        'doctype': 'CRM Lead',
        'id': 'CRM-LEAD-2026-00061',
        'name': 'Fayiq',
        'phones': [
          {'raw': '9087652245', 'e164': '+919087652245', 'valid': true, 'tel_url': 'tel:+919087652245', 'whatsapp_url': 'https://wa.me/919087652245'}
        ],
        'primary_phone': {'raw': '9087652245', 'e164': '+919087652245', 'valid': true, 'tel_url': 'tel:+919087652245', 'whatsapp_url': 'https://wa.me/919087652245'},
      },
    });
    expect(a.state, ActivityState.rescheduled);
    expect(a.isOpen, isTrue);
    expect(a.start!.toUtc(), DateTime.utc(2026, 10, 13, 5, 0));
    expect(a.party!.primaryPhone!.whatsappUrl, 'https://wa.me/919087652245');
  });

  test('unknown display state falls back to pending', () {
    expect(ActivityStateStyle.parse('weird'), ActivityState.pending);
    expect(ActivityStateStyle.parse('active'), ActivityState.active);
  });

  test('every state has a readable label (colour is never the only signal)', () {
    for (final s in ActivityState.values) {
      expect(s.label.isNotEmpty, isTrue);
    }
  });

  test('server address normalisation', () {
    expect(ApiClient.normalizeServer('nexus365.hipersignerp.cloud/'), 'https://nexus365.hipersignerp.cloud');
    expect(ApiClient.normalizeServer(' https://x.example.com// '), 'https://x.example.com');
  });

  test('outgoing timestamps carry an explicit offset', () {
    final s = Repository.iso(DateTime(2026, 10, 13, 10, 30));
    expect(RegExp(r'^2026-10-13T10:30:00[+-]\d\d:\d\d$').hasMatch(s), isTrue);
  });

  test('profile access fingerprint changes with roles', () {
    final a = Profile.fromJson({'user': 'u', 'roles': ['Hipersign Sales'], 'capabilities': {'calendar': true}, 'workspaces': ['sales']});
    final b = Profile.fromJson({'user': 'u', 'roles': ['Hipersign Sales', 'Hipersign Manager'], 'capabilities': {'calendar': true, 'team_view': true}, 'workspaces': ['sales']});
    expect(a.accessKey == b.accessKey, isFalse);
    expect(a.can('calendar'), isTrue);
    expect(a.can('team_view'), isFalse);
  });

  test('idempotency keys are random and long enough', () {
    final k1 = randomKey(16);
    final k2 = randomKey(16);
    expect(k1.length, 32);
    expect(k1 == k2, isFalse);
  });
}
