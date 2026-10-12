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
