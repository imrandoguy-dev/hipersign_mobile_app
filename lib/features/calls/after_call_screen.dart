import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/auth/session.dart';
import '../../core/callerid/call_log_sync.dart';
import '../../core/phone/direct_call.dart';
import '../../core/recordings/recording_service.dart';
import '../../shared/models/models.dart';
import '../activities/activity_form.dart';
import '../customers/customer_detail_screen.dart';
import '../notes/notes.dart';

/// Opened by the phone when a work call ends (like Truecaller's after-call screen), even if
/// Hipersign was closed: saves the call recording and the call log, and offers quick actions.
class AfterCallScreen extends StatefulWidget {
  const AfterCallScreen({super.key, required this.call});

  /// number, direction (incoming | outgoing | missed), duration (s), name, doctype, id
  final Map<String, dynamic> call;

  @override
  State<AfterCallScreen> createState() => _AfterCallScreenState();
}

class _AfterCallScreenState extends State<AfterCallScreen> {
  final _rec = RecordingService.instance;
  final List<Timer> _timers = [];
  final DateTime _openedAt = DateTime.now();

  String get _number => widget.call['number']?.toString() ?? '';
  String get _direction => widget.call['direction']?.toString() ?? 'outgoing';
  int get _seconds => (widget.call['duration'] as num?)?.toInt() ?? 0;
  bool get _missed => _direction == 'missed';
  bool get _connected => !_missed && _seconds > 0;

  Party? get _party {
    final doctype = widget.call['doctype']?.toString();
    final id = widget.call['id']?.toString();
    if (doctype == null || doctype.isEmpty || id == null || id.isEmpty) return null;
    final kind = switch (doctype) {
      'CRM Lead' => 'Lead',
      'CRM Deal' => 'Deal',
      _ => 'Customer',
    };
    return Party(kind: kind, doctype: doctype, id: id, name: widget.call['name']?.toString() ?? id);
  }

  @override
  void initState() {
    super.initState();
    clearAfterCallNotification();
    _rec.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _save();
      // The phone may need a few seconds to finish writing the recording file.
      for (final s in [6, 15, 30]) {
        _timers.add(Timer(Duration(seconds: s), _save));
      }
    });
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _rec.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (!mounted) return;
    final session = context.read<SessionController>();
    final p = session.profile;
    if (p == null) return;
    await _rec.bind(p.user, enabled: p.can('call_recordings'));
    try {
      await _rec.sync(session.repo);
    } catch (_) {}
    try {
      await syncCallLog(session.repo, p.user, force: true);
    } catch (_) {}
  }

  String _last9(String s) {
    final d = s.replaceAll(RegExp(r'[^0-9]'), '');
    return d.length > 9 ? d.substring(d.length - 9) : d;
  }

  /// This call's entry in the recordings list (same number, ended just now).
  CallEntry? get _entry {
    final key = _last9(_number);
    final since = _openedAt.subtract(Duration(seconds: _seconds + 300));
    final matches = _rec.entries.where((e) => _last9(e.number) == key && (e.callAt ?? e.startedAt).isAfter(since)).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return matches.firstOrNull;
  }

  String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  void _done() {
    Navigator.of(context).maybePop();
    SystemNavigator.pop(); // back to where the user was (the call / home screen)
  }

  @override
  Widget build(BuildContext context) {
    final party = _party;
    final name = widget.call['name']?.toString() ?? _number;
    final entry = _entry;
    final recordingsOn = _rec.enabled;
    final (IconData icon, String what) = switch (_direction) {
      'incoming' => (Icons.call_received, 'Incoming call'),
      'missed' => (Icons.call_missed, 'Missed call'),
      _ => (Icons.call_made, 'Outgoing call'),
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call ended'),
        actions: [IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: _done)],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: HsColors.card, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: _missed ? HsColors.danger : HsColors.blue),
              const SizedBox(width: 8),
              Text(_connected ? '$what · ${_fmt(_seconds)}' : (_missed ? what : '$what · not connected'),
                  style: const TextStyle(color: HsColors.textSecondary, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 10),
            Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: HsColors.navy)),
            if (party != null) Text(party.kind, style: const TextStyle(color: HsColors.textSecondary)),
            Text(_number, style: const TextStyle(color: HsColors.textSecondary)),
            if (_connected && recordingsOn) ...[
              const Divider(height: 28),
              Row(children: [
                if (entry == null || entry.status == CallEntry.waiting || entry.status == CallEntry.uploading)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(
                    entry.status == CallEntry.uploaded ? Icons.check_circle : Icons.info_outline,
                    color: entry.status == CallEntry.uploaded ? HsColors.completed : HsColors.warning,
                    size: 20,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry == null
                        ? 'Saving the call...'
                        : (entry.status == CallEntry.uploaded ? 'Recording saved to ERP' : entry.statusLabel),
                  ),
                ),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: 20),
        if (_missed)
          FilledButton.icon(
            icon: const Icon(Icons.call),
            label: const Text('Call back'),
            onPressed: () async {
              await RecordingService.instance.noteCall(
                number: _number,
                partyDoctype: party?.doctype,
                party: party?.id,
                partyName: party?.name,
              );
              await placeCall(_number);
            },
          ),
        if (_missed) const SizedBox(height: 10),
        if (party != null) ...[
          FilledButton.icon(
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Add note about this call'),
            onPressed: () => openNoteEditor(context, doctype: party.doctype, name: party.id, partyName: party.name),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.phone_callback_outlined),
            label: const Text('Add follow-up'),
            onPressed: () => openActivityForm(context, type: 'Follow-up', party: party),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.groups_2_outlined),
            label: const Text('Schedule meeting'),
            onPressed: () => openActivityForm(context, type: 'Meeting', party: party),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: Text('Open ${party.kind.toLowerCase()}'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CustomerDetailScreen(doctype: party.doctype, name: party.id, title: party.name)),
            ),
          ),
          const SizedBox(height: 10),
        ],
        TextButton(onPressed: _done, child: const Text('Done')),
      ]),
    );
  }
}
