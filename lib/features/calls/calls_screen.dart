import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/calls.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/contact_actions.dart';
import '../customers/customer_detail_screen.dart';
import '../customers/dialer_sheet.dart';
import '../recordings/recording_widgets.dart';

const _filters = {
  'all': 'All',
  'new_not_reached': 'New leads not reached',
  'not_reached': 'All not reached',
  'connected': 'Connected',
  'not_connected': 'Not answered',
  'incoming': 'Incoming',
  'missed': 'Missed',
};

/// "1 h 05 min" / "4 min" / "45 s"
String talkTime(int seconds) {
  if (seconds < 60) return '$seconds s';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return h > 0 ? '$h h ${m.toString().padLeft(2, '0')} min' : '$m min';
}

/// Latest work calls with customers / leads / deals (like the phone's call log, work calls only).
class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key, this.initialFilter = 'all'});
  final String initialFilter; // e.g. 'new_not_reached' from the target banner

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  final _q = TextEditingController();
  final _player = RecordingPlayer();
  Timer? _debounce;
  String _scope = 'mine';
  late String _filter = widget.initialFilter;
  List<CallEntry> _items = [];
  Map<String, int>? _today;
  String? _next;
  bool _loading = false;
  bool _loadingMore = false;
  ApiException? _error;
  DateTime? _syncedAt;

  @override
  void initState() {
    super.initState();
    refreshTick.addListener(_load);
    _fromCache();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    refreshTick.removeListener(_load);
    _debounce?.cancel();
    _player.dispose();
    _q.dispose();
    super.dispose();
  }

  void _fromCache() {
    final c = context.read<SessionController>().repo.cachedCalls(_scope, _filter);
    if (c != null) {
      _items = c.items;
      _today = c.today;
      _next = c.nextCursor;
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final query = _q.text.trim();
    setState(() => _loading = true);
    try {
      final page = await context
          .read<SessionController>()
          .repo
          .calls(scope: _scope, filter: _filter, query: query.isEmpty ? null : query);
      if (!mounted || query != _q.text.trim()) return;
      setState(() {
        _items = page.items;
        _next = page.nextCursor;
        _today = page.today ?? _today;
        _error = null;
        _syncedAt = DateTime.now();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (_next == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final q = _q.text.trim();
      final page = await context
          .read<SessionController>()
          .repo
          .calls(scope: _scope, filter: _filter, query: q.isEmpty ? null : q, cursor: _next);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _next = page.nextCursor;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// "New leads not reached (12)" - how many to call back.
  String _chipLabel(String key, String label) {
    final n = key == 'new_not_reached' ? _today?['new_not_reached'] : (key == 'not_reached' ? _today?['not_reached'] : null);
    return n == null || n == 0 ? label : '$label ($n)';
  }

  void _set({String? scope, String? filter}) {
    setState(() {
      _scope = scope ?? _scope;
      _filter = filter ?? _filter;
      _items = [];
      _next = null;
      _fromCache();
    });
    _load();
  }

  void _open(CallEntry c) {
    final p = c.party;
    if (p != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(doctype: p.doctype, name: p.id, title: p.name)));
    } else {
      openDialer(context, number: c.phone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = context.watch<SessionController>().profile?.can('team_view') ?? false;
    final rows = <Widget>[];
    DateTime? lastDay;
    for (final c in _items) {
      final at = c.at;
      if (at != null && (lastDay == null || !_sameDay(lastDay, at))) {
        lastDay = at;
        rows.add(SectionHeader(relativeDay(at)));
      }
      rows.add(_CallRow(call: c, player: _player, showCaller: _scope == 'team', onTap: () => _open(c)));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Calls', style: TextStyle(fontWeight: FontWeight.w700))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) _more();
            return false;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              if (team)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'mine', label: Text('My calls')),
                      ButtonSegment(value: 'team', label: Text('Team')),
                    ],
                    selected: {_scope},
                    onSelectionChanged: (s) => _set(scope: s.first),
                  ),
                ),
              if (_today != null) _TodayCard(today: _today!, team: _scope == 'team'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  controller: _q,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search name or number',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _q.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _q.clear();
                              _load();
                            },
                          ),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 350), _load);
                  },
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  children: [
                    for (final f in _filters.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(label: Text(_chipLabel(f.key, f.value)), selected: _filter == f.key, onSelected: (_) => _set(filter: f.key)),
                      ),
                  ],
                ),
              ),
              if (_error != null) SyncBanner(error: _error, syncedAt: _syncedAt),
              if (_loading && _items.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
              if (!_loading && _items.isEmpty && _error == null)
                EmptyState(
                  icon: _filter.endsWith('not_reached') ? Icons.check_circle_outline : Icons.call_outlined,
                  title: _filter.endsWith('not_reached') ? 'Everyone has been reached' : 'No calls here yet',
                  message: _filter.endsWith('not_reached')
                      ? 'Numbers you called that never picked up show here until a call connects.'
                      : 'Calls with customers, leads and deals appear here a moment after they end.',
                ),
              ...rows,
              if (_loadingMore) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            ],
          ),
        ),
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.today, required this.team});
  final Map<String, int> today;
  final bool team;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) => Expanded(
          child: Column(children: [
            Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: HsColors.navy)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: HsColors.textSecondary)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      decoration: BoxDecoration(color: HsColors.card, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(team ? "Team's calls today" : 'My calls today', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Row(children: [
          stat('Calls', '${today['total'] ?? 0}'),
          stat('Connected', '${today['connected'] ?? 0}'),
          stat('New', '${today['new_calls'] ?? 0}'),
          stat('Follow-ups', '${today['followups'] ?? 0}'),
          stat('Talk time', talkTime(today['talk'] ?? 0)),
        ]),
      ]),
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.call, required this.player, required this.showCaller, required this.onTap});

  final CallEntry call;
  final RecordingPlayer player;
  final bool showCaller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = call;
    final (IconData icon, Color color, String what) = switch (c.direction) {
      'Incoming' => (Icons.call_received, HsColors.blue, 'Incoming'),
      'Missed' => (Icons.call_missed, HsColors.danger, 'Missed'),
      _ => c.connected
          ? (Icons.call_made, const Color(0xFF2E7D32), 'Outgoing')
          : (Icons.call_made, HsColors.danger, 'Not answered'),
    };
    final tries = c.attempts;
    final details = tries != null
        ? [
            tries == 1 ? '1 try' : '$tries tries',
            if (c.firstAt != null && tries > 1) 'since ${relativeDay(c.firstAt!)}',
            if (c.partyKind != null) c.partyKind!,
            if (showCaller && c.callerName != null) c.callerName!,
          ].join(' · ')
        : [
      what,
      if (c.connected) fmtDuration(c.duration),
      if (c.callType != null) c.callType!,
      if (c.partyKind != null) c.partyKind!,
      if (showCaller && c.callerName != null) c.callerName!,
    ].join(' · ');
    final phone = PhoneInfo(raw: c.phone, e164: c.phone, valid: c.phone.isNotEmpty, telUrl: 'tel:${c.phone}');
    return Column(children: [
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            CircleAvatar(radius: 20, backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: HsColors.textSecondary)),
              ]),
            ),
            Text(fmtTime(c.at), style: const TextStyle(fontSize: 12, color: HsColors.textSecondary)),
            if (c.recordingId != null)
              ListenableBuilder(
                listenable: player,
                builder: (context, _) {
                  final loading = player.loadingId == c.id;
                  final playing = player.isPlaying(c.id);
                  return IconButton(
                    tooltip: playing ? 'Pause recording' : 'Play recording',
                    onPressed: () => player.toggle(
                      c.id,
                      () => context.read<SessionController>().repo.callRecordingFile(c.recordingId!, c.recordingExt),
                    ),
                    icon: loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_outline, color: HsColors.navy),
                  );
                },
              ),
            IconButton(
              tooltip: 'Call again',
              icon: const Icon(Icons.call_outlined),
              onPressed: () => callPhone(phone, party: c.party),
            ),
          ]),
        ),
      ),
      if (c.recordingId != null)
        ListenableBuilder(
          listenable: player,
          builder: (context, _) => player.currentId == c.id && player.loadingId == null
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(68, 0, 16, 6),
                  child: StreamBuilder<Duration>(
                    stream: player.position,
                    builder: (context, snap) {
                      final total = player.duration.inMilliseconds;
                      final pos = (snap.data ?? Duration.zero).inMilliseconds;
                      return Row(children: [
                        Expanded(child: LinearProgressIndicator(value: total <= 0 ? 0 : (pos / total).clamp(0, 1).toDouble(), minHeight: 3)),
                        const SizedBox(width: 8),
                        Text('${fmtDuration(pos ~/ 1000)} / ${fmtDuration(total ~/ 1000)}', style: const TextStyle(fontSize: 11.5)),
                      ]);
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),
    ]);
  }
}
