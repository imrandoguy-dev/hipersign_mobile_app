import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../core/recordings/recording_service.dart';
import '../../shared/maps/maps_links.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/activity_card.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/contact_actions.dart';
import '../activities/activity_detail_screen.dart';
import '../activities/activity_form.dart';
import '../notes/notes.dart';
import '../recordings/recording_widgets.dart';
import '../recordings/recordings_screen.dart';
import '../trials/book_trial_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.doctype, required this.name, required this.title});

  final String doctype;
  final String name;
  final String title;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  Party? _party;
  List<Activity> _activities = [];
  Activity? _next;
  ApiException? _error;
  bool _loading = true;
  List<CallRecording> _recordings = [];
  List<Note>? _notes;
  final _player = RecordingPlayer();

  bool get _showRecordings =>
      Platform.isAndroid && (context.read<SessionController>().profile?.can('call_recordings') ?? false);

  @override
  void initState() {
    super.initState();
    RecordingService.instance.addListener(_onRecordings);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    RecordingService.instance.removeListener(_onRecordings);
    _player.dispose();
    super.dispose();
  }

  int _uploadedCount = -1;

  void _onRecordings() {
    final n = RecordingService.instance.entries.where((e) => e.status == CallEntry.uploaded).length;
    if (n != _uploadedCount) {
      _uploadedCount = n;
      _loadRecordings();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadNotes() async {
    try {
      final n = await context.read<SessionController>().repo.partyNotes(widget.doctype, widget.name);
      if (mounted) setState(() => _notes = n);
    } on ApiException {
      // Notes are extra; the page still works without them (e.g. older server).
    }
  }

  Future<void> _addNote(Party p) async {
    if (await openNoteEditor(context, doctype: p.doctype, name: p.id, partyName: p.name)) _loadNotes();
  }

  List<Widget> _notesSection(Party p) {
    final notes = _notes ?? const <Note>[];
    return [
      SectionHeader('Notes', count: notes.length),
      if (_notes != null && notes.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('No notes yet.', style: TextStyle(color: HsColors.textSecondary)),
        ),
      for (final n in notes.take(3))
        NoteCard(
          note: n,
          onTap: () async {
            if (await openNote(context, doctype: p.doctype, name: p.id, partyName: p.name, note: n)) _loadNotes();
          },
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: Row(children: [
          TextButton.icon(
            icon: const Icon(Icons.note_add_outlined, size: 18),
            label: const Text('Add note'),
            onPressed: () => _addNote(p),
          ),
          if (notes.length > 3)
            TextButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => NotesScreen(doctype: p.doctype, name: p.id, partyName: p.name)),
                );
                _loadNotes();
              },
              child: Text('All ${notes.length} notes'),
            ),
        ]),
      ),
    ];
  }

  Future<void> _loadRecordings() async {
    if (!mounted || !_showRecordings) return;
    try {
      final page = await context.read<SessionController>().repo.recordings(partyDoctype: widget.doctype, party: widget.name);
      if (mounted) setState(() => _recordings = page.items);
    } on ApiException {
      // Recordings are extra; the customer page still works without them.
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<SessionController>().repo.partyDetail(widget.doctype, widget.name);
      if (!mounted) return;
      setState(() {
        _party = Party.fromJson(d);
        _activities = ((d['activities'] as List?) ?? const [])
            .map((e) => Activity.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        _next = d['next_activity'] is Map ? Activity.fromJson(Map<String, dynamic>.from(d['next_activity'] as Map)) : null;
        _error = null;
      });
      _loadRecordings();
      _loadNotes();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _party;
    final profile = context.read<SessionController>().profile!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: p == null
          ? (_loading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: EmptyState(
                    icon: Icons.error_outline,
                    title: 'Could not load this customer',
                    message: _error?.message,
                    action: FilledButton(onPressed: _load, child: const Text('Try again')),
                  ),
                ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
                if (_error != null) SyncBanner(error: _error),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: HsColors.card, borderRadius: BorderRadius.circular(20)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text([p.kind, if (p.subtitle != null) p.subtitle!, if (p.status != null) p.status!].join(' - '),
                        style: const TextStyle(color: HsColors.textSecondary)),
                    if (p.email != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: InkWell(
                          onTap: () => launchUrl(Uri(scheme: 'mailto', path: p.email)),
                          child: Row(children: [
                            const Icon(Icons.mail_outline, size: 18, color: HsColors.textSecondary),
                            const SizedBox(width: 8),
                            Text(p.email!),
                          ]),
                        ),
                      ),
                    if (p.phones.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('No phone number in ERP.', style: TextStyle(color: HsColors.textSecondary)),
                      ),
                    for (final ph in p.phones)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(ph.e164 ?? ph.raw, style: const TextStyle(fontSize: 15)),
                              Text(ph.valid ? (ph.label ?? 'Phone') : 'Invalid number - fix in ERP',
                                  style: TextStyle(fontSize: 12, color: ph.valid ? HsColors.textSecondary : HsColors.danger)),
                            ]),
                          ),
                          ContactButtons(phone: ph, party: p),
                        ]),
                      ),
                    ..._locationRows(p),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    ActionChip(
                      avatar: const Icon(Icons.note_add_outlined, size: 18),
                      label: const Text('Note'),
                      onPressed: () => _addNote(p),
                    ),
                    if (profile.can('create_activity'))
                      ActionChip(
                        avatar: const Icon(Icons.phone_callback_outlined, size: 18),
                        label: const Text('Follow-up'),
                        onPressed: () async {
                          await openActivityForm(context, type: 'Follow-up', party: p);
                          _load();
                        },
                      ),
                    if (profile.can('create_activity'))
                      ActionChip(
                        avatar: const Icon(Icons.groups_2_outlined, size: 18),
                        label: const Text('Meeting'),
                        onPressed: () async {
                          await openActivityForm(context, type: 'Meeting', party: p);
                          _load();
                        },
                      ),
                    if (profile.can('trial_booking') && p.doctype != 'CRM Deal')
                      ActionChip(
                        avatar: const Icon(Icons.school_outlined, size: 18),
                        label: const Text('Book trial'),
                        onPressed: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => BookTrialScreen(party: p)));
                          _load();
                        },
                      ),
                  ]),
                ),
                ..._notesSection(p),
                if (_next != null) ...[
                  const SectionHeader('Next activity'),
                  ActivityCard(activity: _next!, onTap: () => _open(_next!)),
                ],
                SectionHeader('Your activities', count: _activities.length),
                if (_activities.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text('No activities with this customer yet.', style: TextStyle(color: HsColors.textSecondary)),
                  ),
                for (final a in _activities) ActivityCard(activity: a, onTap: () => _open(a)),
                if (_showRecordings) ..._recordingSection(p),
              ]),
            ),
    );
  }

  Future<void> _openMaps(Uri uri) async {
    if (!await MapsLinks.open(uri)) showSnack('Could not open Google Maps', error: true);
  }

  /// Address with Directions (Google Maps) and the Google Business profile.
  List<Widget> _locationRows(Party p) {
    final links = MapsLinks(p.name, p.location);
    final address = p.location?.address;
    return [
      const Padding(padding: EdgeInsets.only(top: 14), child: Divider(height: 1)),
      InkWell(
        onTap: links.hasLocation ? () => _openMaps(links.pin()) : null,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.location_on_outlined, size: 20, color: HsColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                address ?? (links.hasLocation ? 'Location on Google Maps' : 'No address in ERP'),
                style: TextStyle(color: address == null ? HsColors.textSecondary : null, height: 1.35),
              ),
            ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.directions_outlined, size: 18),
            label: const Text('Directions'),
            onPressed: () => _openMaps(links.directions()),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.storefront_outlined, size: 18),
            label: const Text('Google Business'),
            onPressed: () => _openMaps(links.business()),
          ),
        ]),
      ),
    ];
  }

  List<Widget> _recordingSection(Party p) {
    final repo = context.read<SessionController>().repo;
    final waiting = RecordingService.instance.pending
        .where((e) => e.party == p.id && e.partyDoctype == p.doctype && e.status != CallEntry.notFound)
        .toList();
    return [
      SectionHeader('Call recordings', count: _recordings.length),
      if (_recordings.isEmpty && waiting.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('No call recordings yet.', style: TextStyle(color: HsColors.textSecondary)),
        ),
      for (final e in waiting)
        RecordingRow(
          id: 'local:${e.id}',
          title: 'Call ${fmtDayTime(e.startedAt)}',
          subtitle: e.statusLabel,
          player: _player,
          resolvePath: e.hasRecording ? () => RecordingService.instance.localFile(e) : null,
        ),
      for (final r in _recordings)
        RecordingRow(
          id: r.id,
          title: fmtDayTime(r.startedAt),
          subtitle: [
            fmtDuration(r.durationSeconds),
            if (r.recordedByName != null) 'by ${r.recordedByName}',
          ].join('  ·  '),
          player: _player,
          resolvePath: () => repo.recordingFile(r),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.graphic_eq, size: 18),
            label: const Text('All call recordings'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecordingsScreen())),
          ),
        ),
      ),
    ];
  }

  Future<void> _open(Activity a) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: a.id)));
    _load();
  }
}
