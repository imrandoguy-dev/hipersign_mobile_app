import 'package:flutter_test/flutter_test.dart';
import 'package:hipersign_mobile_app/core/phone/direct_call.dart';
import 'package:hipersign_mobile_app/core/recordings/recording_service.dart';

PhoneAudioFile file(String uri, String name, DateTime added, {String path = 'Music/Recordings/Call Recordings/', int size = 5000}) =>
    PhoneAudioFile({
      'uri': uri,
      'name': name,
      'path': path,
      'size': size,
      'duration': 60000,
      'added': added.millisecondsSinceEpoch,
      'modified': added.millisecondsSinceEpoch,
    });

void main() {
  final start = DateTime(2026, 10, 12, 10, 0);

  test('file named with the number wins', () {
    final pick = pickRecording(number: '+919847012345', startedAt: start, files: [
      file('a', 'Call_9061234567_20261012.m4a', start.add(const Duration(minutes: 1))),
      file('b', 'Arjun 98470 12345_20261012.m4a', start.add(const Duration(minutes: 2))),
    ]);
    expect(pick?.uri, 'b');
  });

  test('otherwise the first file in a call-recording folder', () {
    final pick = pickRecording(number: '9847012345', startedAt: start, files: [
      file('voice', 'Voice 001.m4a', start.add(const Duration(minutes: 1)), path: 'Recordings/Voice Recorder/'),
      file('call', 'Arjun_20261012.m4a', start.add(const Duration(minutes: 3))),
    ]);
    expect(pick?.uri, 'call');
  });

  test('ignores files before the call, after the next call, used or empty', () {
    final files = [
      file('old', 'call_9847012345.m4a', start.subtract(const Duration(minutes: 5))),
      file('used', 'call_9847012345.m4a', start.add(const Duration(minutes: 1))),
      file('empty', 'call_9847012345.m4a', start.add(const Duration(minutes: 1)), size: 0),
      file('late', 'call_9847012345.m4a', start.add(const Duration(minutes: 20))),
    ];
    expect(
      pickRecording(
        number: '9847012345',
        startedAt: start,
        nextCallAt: start.add(const Duration(minutes: 10)),
        files: files,
        used: {'used'},
      ),
      isNull,
    );
    expect(pickRecording(number: '9847012345', startedAt: start, files: files, used: {'used'})?.uri, 'late');
  });

  test('Xiaomi: number in the folder, contact name in the file', () {
    final pick = pickRecording(number: '+919495771084', startedAt: start, files: [
      file('other', '1791808000924.aac', start.add(const Duration(seconds: 20)), path: 'Music/'),
      file('xiaomi', 'Hipersign ERP-20261012175629.aac', start.add(const Duration(seconds: 40)),
          path: 'Music/PhoneRecord/9495771084/'),
    ]);
    expect(pick?.uri, 'xiaomi');
  });

  test('call-recording folders are recognised', () {
    for (final path in ['Music/PhoneRecord/', 'MIUI/sound_recorder/call_rec/', 'Recordings/Call/', 'Sounds/CallRecord/']) {
      expect(looksLikeCallRecording(file('x', 'Someone.m4a', start, path: path)), isTrue, reason: path);
    }
    expect(looksLikeCallRecording(file('x', 'Voice 001.m4a', start, path: 'Recordings/Voice Recorder/')), isFalse);
  });

  test('bug: a cancelled call never takes the next caller\'s recording (Xiaomi folders)', () {
    // Our call to 98470 12345 was cancelled; an incoming call from 94957 71084 was recorded.
    final pick = pickRecording(number: '+919847012345', startedAt: start, files: [
      file('incoming', 'Hipersign ERP-20261012101530.aac', start.add(const Duration(minutes: 3)),
          path: 'Music/PhoneRecord/9495771084/'),
    ]);
    expect(pick, isNull);
  });

  test('timestamps in names are not phone numbers', () {
    final f = file('a', 'Arjun-20261012175629.aac', start.add(const Duration(seconds: 30)), path: 'Recordings/Call/');
    expect(mentionsOtherNumber(f, '+919847012345'), isFalse);
    expect(pickRecording(number: '+919847012345', startedAt: start, files: [f])?.uri, 'a');
  });

  test('known call length keeps the window tight', () {
    final late = file('late', 'Someone.m4a', start.add(const Duration(minutes: 20)), path: 'Recordings/Call/');
    expect(pickRecording(number: '9847012345', startedAt: start, callSeconds: 60, files: [late]), isNull);
    expect(pickRecording(number: '9847012345', startedAt: start, files: [late])?.uri, 'late');
  });

  test('call entry survives a save/load round trip', () {
    final e = CallEntry(id: 'x1', number: '+919847012345', startedAt: start, party: 'C-1', partyDoctype: 'Customer', partyName: 'Malabar')
      ..status = CallEntry.found
      ..uri = 'content://media/1';
    final back = CallEntry.fromJson(e.toJson());
    expect(back.party, 'C-1');
    expect(back.status, CallEntry.found);
    expect(back.hasRecording, isTrue);
    expect(back.startedAt, start);
    final incoming = CallEntry.fromJson((CallEntry(id: 'x2', number: '1', startedAt: start)
          ..incoming = true
          ..callSeconds = 42
          ..callAt = start
          ..logChecked = true)
        .toJson());
    expect([incoming.incoming, incoming.callSeconds, incoming.logChecked, incoming.callAt], [true, 42, true, start]);
  });
}
