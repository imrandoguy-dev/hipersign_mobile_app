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

  test('call entry survives a save/load round trip', () {
    final e = CallEntry(id: 'x1', number: '+919847012345', startedAt: start, party: 'C-1', partyDoctype: 'Customer', partyName: 'Malabar')
      ..status = CallEntry.found
      ..uri = 'content://media/1';
    final back = CallEntry.fromJson(e.toJson());
    expect(back.party, 'C-1');
    expect(back.status, CallEntry.found);
    expect(back.hasRecording, isTrue);
    expect(back.startedAt, start);
  });
}
