import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../core/phone/direct_call.dart';
import '../../core/recordings/recording_service.dart';
import '../../core/repository.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../customers/customer_detail_screen.dart';
import '../customers/new_lead.dart';
import '../customers/party_picker.dart';
import 'recording_widgets.dart';

String _when(DateTime? d) {
  if (d == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final time = DateFormat.jm().format(d);
  if (day == today) return 'Today, $time';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday, $time';
  return '${DateFormat('d MMM').format(d)}, $time';
}

/// Call recordings like a phone's call log: calls waiting for their recording on top,
/// recordings saved in ERP below. Tap to play.
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> with WidgetsBindingObserver {
  final _player = RecordingPlayer();
  final _service = RecordingService.instance;
  List<CallRecording> _items = [];
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shownUploads.addAll(_service.entries.where((e) => e.status == CallEntry.uploaded).map((e) => e.id));
    _service.addListener(_onService);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(ask: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.removeListener(_onService);
    _player.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(); // back from phone settings
  }

  final Set<String> _shownUploads = {};

  void _onService() {
    if (!mounted) return;
    setState(() {});
    // A recording just finished uploading: reload the saved list once to show it.
    final fresh = _service.entries
        .where((e) => e.status == CallEntry.uploaded && !_shownUploads.contains(e.id))
        .map((e) => e.id)
        .toList();
    if (fresh.isNotEmpty) {
      _shownUploads.addAll(fresh);
      _loadServer();
    }
  }

  Future<void> _refresh({bool ask = false}) async {
    final repo = context.read<SessionController>().repo;
    await Future.wait([_service.sync(repo, askPermission: ask), _loadServer()]);
  }

  Future<void> _loadServer() async {
    final repo = context.read<SessionController>().repo;
    try {
      final page = await repo.recordings();
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _cursor = page.nextCursor;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (_cursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await context.read<SessionController>().repo.recordings(cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _cursor = page.nextCursor;
      });
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Link an unlinked call: pick an existing customer/lead, or create a new lead
  /// (name pre-filled from Google Maps when the number is found there).
  Future<void> _link(CallEntry e) async {
    final repo = context.read<SessionController>().repo;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Existing customer or lead'),
            onTap: () => Navigator.pop(ctx, 'existing'),
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_outlined),
            title: const Text('New lead'),
            subtitle: Text(e.number),
            onTap: () => Navigator.pop(ctx, 'new'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    Party? p;
    if (choice == 'existing') {
      p = await pickParty(context);
    } else {
      NumberLookup? info;
      try {
        info = await repo.lookupNumber(e.number);
      } on ApiException {
        info = null;
      }
      if (!mounted) return;
      p = info?.linkable ?? await askNewLead(context, repo, info?.phone ?? e.number, google: info?.google);
    }
    if (p == null || !mounted) return;
    await _service.link(repo, e, p);
  }

  /// Pick one of the phone's recent call recordings and save it to a customer.
  Future<void> _addFromPhone() async {
    var perm = await audioPermission();
    if (perm == 'denied') perm = await _service.requestPermission();
    if (perm == 'blocked') {
      showSnack('Allow "Music and audio" for Hipersign in phone settings first.', error: true);
      await openAppSettings();
      return;
    }
    if (perm != 'granted') return;
    List<PhoneAudioFile> files;
    try {
      files = await _service.recentPhoneRecordings();
    } catch (_) {
      showSnack('Could not read the phone\'s recordings.', error: true);
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<PhoneAudioFile>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: files.isEmpty
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: Text(
                    'No call recordings from the last 3 days were found on this phone.\n\n'
                    'Check that call recording is switched on in your phone\'s Phone app settings.',
                  ),
                )
              : ListView(shrinkWrap: true, children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text('Call recordings on this phone',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: HsColors.navy)),
                  ),
                  for (final f in files)
                    ListTile(
                      leading: const Icon(Icons.graphic_eq, color: HsColors.blue),
                      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${_when(f.added)}  ·  ${fmtDuration((f.durationMs / 1000).round())}'),
                      onTap: () => Navigator.pop(ctx, f),
                    ),
                ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final p = await pickParty(context);
    if (p == null || !mounted) return;
    await _service.addFromPhone(context.read<SessionController>().repo, picked, p);
    final saved = _service.entries.where((e) => e.uri == picked.uri).firstOrNull;
    if (saved?.status == CallEntry.uploaded) showSnack('Saved to ${p.name}');
  }

  Future<void> _delete(CallRecording r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete recording?'),
        content: Text('The recording of the call with ${r.partyName} will be removed from ERP.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HsColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = context.read<SessionController>().repo;
    await runWrite(context, () => repo.deleteRecording(r.id), success: 'Recording deleted');
    if (!mounted) return;
    if (_player.currentId == r.id) await _player.stop();
    await _loadServer();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<SessionController>().profile?.user;
    final repo = context.read<SessionController>().repo;
    final pending = _service.pending;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call recordings', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_service.supported)
            IconButton(
              tooltip: 'Add a recording from this phone',
              icon: const Icon(Icons.library_add_outlined),
              onPressed: _addFromPhone,
            ),
          IconButton(
            tooltip: 'How it works',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showRecordingHelp(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) _more();
            return false;
          },
          child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            if (_service.supported) _PermissionCard(service: _service),
            if (_error != null) SyncBanner(error: _error),
            if (pending.isNotEmpty) ...[
              SectionHeader('On this phone', count: pending.length),
              for (final e in pending)
                RecordingRow(
                  id: 'local:${e.id}',
                  title: e.title,
                  subtitle: [
                    if (e.incoming) 'Incoming',
                    _when(e.startedAt),
                    if (e.durationMs > 0) fmtDuration((e.durationMs / 1000).round()),
                    if (e.partyName != null) e.number,
                  ].join('  ·  '),
                  status: e.statusLabel,
                  statusColor: switch (e.status) {
                    CallEntry.failed || CallEntry.unlinked => HsColors.warning,
                    CallEntry.notFound => HsColors.danger,
                    _ => HsColors.blue,
                  },
                  player: _player,
                  resolvePath: e.hasRecording ? () => _service.localFile(e) : null,
                  trailing: _pendingAction(e, repo),
                ),
            ],
            SectionHeader('Saved in ERP', count: _items.length),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'No recordings yet. Call a customer from Hipersign - the recording appears here after the call.',
                  style: TextStyle(color: HsColors.textSecondary),
                ),
              ),
            for (final r in _items)
              RecordingRow(
                id: r.id,
                title: r.partyName,
                subtitle: [
                  _when(r.startedAt),
                  fmtDuration(r.durationSeconds),
                  if (r.recordedBy != null && r.recordedBy != me) 'by ${r.recordedByName ?? r.recordedBy}',
                ].join('  ·  '),
                player: _player,
                resolvePath: () => repo.recordingFile(r),
                onLongPress: () => _delete(r),
                trailing: PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert, color: HsColors.textSecondary),
                  onSelected: (v) {
                    if (v == 'open') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CustomerDetailScreen(doctype: r.partyDoctype, name: r.party, title: r.partyName),
                        ),
                      );
                    } else if (v == 'delete') {
                      _delete(r);
                    }
                  },
                  itemBuilder: (_) => [
                    if (r.party.isNotEmpty) const PopupMenuItem(value: 'open', child: Text('Open customer')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete recording')),
                  ],
                ),
              ),
            if (_loadingMore) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            if (_service.supported) _Diagnostics(service: _service),
          ]),
        ),
      ),
    );
  }

  Widget? _pendingAction(CallEntry e, Repository repo) {
    switch (e.status) {
      case CallEntry.unlinked:
        return TextButton(onPressed: () => _link(e), child: const Text('Link'));
      case CallEntry.failed:
        return TextButton(onPressed: () => _service.retry(repo, e), child: const Text('Retry'));
      case CallEntry.uploading:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      default:
        return IconButton(
          tooltip: 'Remove from this list',
          icon: const Icon(Icons.close, size: 20, color: HsColors.textSecondary),
          onPressed: () => _service.dismiss(e),
        );
    }
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.service});
  final RecordingService service;

  @override
  Widget build(BuildContext context) {
    final state = service.permission;
    if (state == null || state == 'granted' || state == 'unsupported') return const SizedBox.shrink();
    final blocked = state == 'blocked';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: HsColors.warningBg, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        const Icon(Icons.folder_open_outlined, color: HsColors.warning),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            blocked
                ? 'Allow "Music and audio" for Hipersign in phone settings so it can find your call recordings.'
                : 'Allow Hipersign to read audio files so it can find your call recordings.',
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
        TextButton(
          onPressed: () async {
            if (blocked) {
              await openAppSettings();
            } else {
              final r = await service.requestPermission();
              if (r == 'granted' && context.mounted) {
                await service.sync(context.read<SessionController>().repo);
              }
            }
          },
          child: Text(blocked ? 'Settings' : 'Allow'),
        ),
      ]),
    );
  }
}

/// Plain-language setup steps, shown from the Recordings screen and Settings.
Future<void> showRecordingHelp(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('How call recording works', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: HsColors.navy)),
            SizedBox(height: 12),
            Text(
              '1.  Your phone records the call. Turn on automatic call recording once in your phone\'s own Phone app:\n'
              '     Phone app > Settings > Call recording > Record all calls.\n\n'
              '2.  Call customers from Hipersign (any Call button or the dial pad).\n\n'
              '3.  After the call, Hipersign finds that recording and saves it in ERP on the customer, '
              'and on the follow-up or meeting you called from.\n\n'
              'Allow "Music and audio" access when Hipersign asks - that is how it finds the recordings.\n\n'
              'Some phones (for example Pixel or phones using the Google Phone app) keep recordings private, '
              'so they cannot be saved to ERP from those phones.',
              style: TextStyle(height: 1.4),
            ),
          ]),
        ),
      ),
    );

/// Small grey status block - lets support see what the phone found without access to it.
class _Diagnostics extends StatelessWidget {
  const _Diagnostics({required this.service});
  final RecordingService service;

  @override
  Widget build(BuildContext context) {
    final check = service.lastCheck;
    final lines = <String>[
      'Recording: ${service.enabled ? 'on' : 'off (not enabled for this user on the server)'}'
          '  ·  Audio access: ${service.permission ?? 'not checked'}'
          '  ·  Calls tracked: ${service.entries.length}',
      if (check != null) 'Last check: ${DateFormat.jms().format(check)} - ${service.lastFiles.length} audio file(s) found',
      if (service.lastProblem != null) service.lastProblem!,
      for (final f in service.lastFiles) '   $f',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: SelectableText(
        lines.join('\n'),
        style: const TextStyle(fontSize: 11, color: HsColors.textSecondary, height: 1.4),
      ),
    );
  }
}
