import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/phone/direct_call.dart';
import '../../core/recordings/recording_service.dart';
import '../models/models.dart';

/// Calls the number directly (Android) or opens the dialer. Never marks anything as done (FR-034).
///
/// [party] / [activityId] tell the call recorder which customer (and activity) the
/// phone's recording of this call belongs to.
Future<void> callPhone(PhoneInfo? phone, {void Function()? onLaunched, Party? party, String? activityId}) async {
  if (phone == null) {
    showSnack('No phone number saved for this contact.', error: true);
    return;
  }
  if (!phone.valid || phone.telUrl == null) {
    showSnack('"${phone.raw}" is not a valid phone number. Please fix it in ERPNext.', error: true);
    return;
  }
  final number = phone.e164 ?? phone.telUrl!.replaceFirst('tel:', '');
  await RecordingService.instance.noteCall(
    number: number,
    partyDoctype: party?.doctype,
    party: party?.id,
    partyName: party?.name,
    activity: activityId,
  );
  if (await placeCall(number)) onLaunched?.call();
}

/// Opens the WhatsApp chat with this number (app if installed, otherwise browser).
Future<void> openWhatsApp(PhoneInfo? phone, {void Function()? onLaunched}) async {
  if (phone == null) {
    showSnack('No phone number saved for this contact.', error: true);
    return;
  }
  if (!phone.valid || phone.whatsappUrl == null) {
    showSnack('"${phone.raw}" is not a valid WhatsApp number. Please fix it in ERPNext.', error: true);
    return;
  }
  final ok = await launchUrl(Uri.parse(phone.whatsappUrl!), mode: LaunchMode.externalApplication);
  if (!ok) {
    showSnack('Could not open WhatsApp.', error: true);
  } else {
    onLaunched?.call();
  }
}

class ContactButtons extends StatelessWidget {
  const ContactButtons({
    super.key,
    required this.phone,
    this.onCall,
    this.onWhatsApp,
    this.dark = false,
    this.party,
    this.activityId,
  });

  final PhoneInfo? phone;
  final Party? party; // links the call recording to this customer / lead
  final String? activityId;
  final VoidCallback? onCall;
  final VoidCallback? onWhatsApp;
  final bool dark; // true when drawn on a pastel card

  @override
  Widget build(BuildContext context) {
    final fg = dark ? HsColors.onPastel : HsColors.textPrimary;
    final bg = dark ? Colors.black.withValues(alpha: 0.08) : HsColors.cardHigh;
    final disabled = phone == null || !phone!.valid;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _RoundIcon(
        tooltip: 'WhatsApp',
        icon: Icons.chat,
        color: disabled ? fg.withValues(alpha: 0.35) : HsColors.whatsapp,
        background: bg,
        onTap: () => openWhatsApp(phone, onLaunched: onWhatsApp),
      ),
      const SizedBox(width: 8),
      _RoundIcon(
        tooltip: 'Call',
        icon: Icons.call,
        color: disabled ? fg.withValues(alpha: 0.35) : fg,
        background: bg,
        onTap: () => callPhone(phone, onLaunched: onCall, party: party, activityId: activityId),
      ),
    ]);
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.color, required this.background, required this.onTap, required this.tooltip});

  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 44, height: 44, child: Icon(icon, color: color, size: 22)),
          ),
        ),
      ),
    );
  }
}
