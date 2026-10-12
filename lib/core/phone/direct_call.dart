import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/nav.dart';

const _channel = MethodChannel('hipersign/phone');

/// Places the call straight from Hipersign on Android (no "choose an app" screen).
/// The first call asks for the Phone permission; if it's refused we fall back to the dialer.
/// Returns true when a call or the dialer was opened.
Future<bool> placeCall(String number) async {
  final clean = number.replaceAll(RegExp(r'[^0-9+*#]'), '');
  if (clean.isEmpty) return false;
  if (Platform.isAndroid) {
    try {
      final r = await _channel.invokeMethod<String>('call', {'number': clean});
      if (r == 'called') return true;
      if (r == 'blocked') {
        showSnack('To call directly, allow "Phone" for Hipersign in phone Settings > Apps > Hipersign > Permissions.');
      }
    } on MissingPluginException {
      // Older build without the channel - use the dialer.
    } on PlatformException {
      // Fall through to the dialer.
    }
  }
  final ok = await launchUrl(Uri(scheme: 'tel', path: clean));
  if (!ok) showSnack('Could not start the call.', error: true);
  return ok;
}

// ------------------------------------------------------------ call recordings (Android)

/// One audio file the phone saved (we look for the phone's own call recordings).
class PhoneAudioFile {
  PhoneAudioFile(Map m)
      : uri = m['uri']?.toString() ?? '',
        name = m['name']?.toString() ?? '',
        path = m['path']?.toString() ?? '',
        size = (m['size'] as num?)?.toInt() ?? 0,
        durationMs = (m['duration'] as num?)?.toInt() ?? 0,
        added = DateTime.fromMillisecondsSinceEpoch((m['added'] as num?)?.toInt() ?? 0),
        modified = DateTime.fromMillisecondsSinceEpoch((m['modified'] as num?)?.toInt() ?? 0);

  final String uri;
  final String name;
  final String path;
  final int size;
  final int durationMs;
  final DateTime added;
  final DateTime modified;
}

/// "granted" | "denied" (can ask) | "blocked" (must be allowed in phone settings) | "unsupported".
Future<String> audioPermission({bool request = false}) async {
  if (!Platform.isAndroid) return 'unsupported';
  try {
    return await _channel.invokeMethod<String>('audioPermission', {'request': request}) ?? 'denied';
  } on MissingPluginException {
    return 'unsupported';
  } on PlatformException {
    return 'denied';
  }
}

Future<List<PhoneAudioFile>> findPhoneRecordings(DateTime since, DateTime until) async {
  if (!Platform.isAndroid) return [];
  final list = await _channel.invokeMethod<List<dynamic>>('findRecordings', {
    'since': since.millisecondsSinceEpoch,
    'until': until.millisecondsSinceEpoch,
  });
  return (list ?? const []).whereType<Map>().map(PhoneAudioFile.new).toList();
}

/// Copies a phone recording into the app's cache; returns the file path.
Future<String> copyPhoneRecording(String uri, String name) async {
  final path = await _channel.invokeMethod<String>('copyRecording', {'uri': uri, 'name': name});
  if (path == null) throw PlatformException(code: 'COPY_FAILED');
  return path;
}

Future<void> openAppSettings() async {
  try {
    await _channel.invokeMethod<bool>('openAppSettings');
  } catch (_) {}
}

// ------------------------------------------------------------ phone links opened in Hipersign

/// Number from the phone link that opened the app (e.g. Google's Call button), once.
Future<String?> takeDialIntent() async {
  if (!Platform.isAndroid) return null;
  try {
    return await _channel.invokeMethod<String>('takeDialIntent');
  } catch (_) {
    return null;
  }
}

/// Called when a phone link opens Hipersign while it is already running.
void onDialIntent(void Function(String number)? handler) {
  _channel.setMethodCallHandler(handler == null
      ? null
      : (call) async {
          if (call.method == 'dialIntent' && call.arguments is String) {
            handler(call.arguments as String);
            await takeDialIntent(); // consumed
          }
        });
}
