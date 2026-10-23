import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/team.dart';
import '../../shared/widgets/common.dart';
import '../reports/daily_report_screen.dart';

/// Calendar banner for callers: today's calls against the target ("34 more calls needed").
class TargetBanner extends StatefulWidget {
  const TargetBanner({super.key});

  @override
  State<TargetBanner> createState() => _TargetBannerState();
}

class _TargetBannerState extends State<TargetBanner> {
  TargetProgress? _p;

  @override
  void initState() {
    super.initState();
    _p = context.read<SessionController>().repo.cachedTarget();
    refreshTick.addListener(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    refreshTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await context.read<SessionController>().repo.myTarget();
      if (mounted) setState(() => _p = p);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null || (p.target <= 0 && p.meetingTarget <= 0) || !p.workingDay) return const SizedBox.shrink();
    final frac = p.target <= 0 ? 1.0 : (p.counted / p.target).clamp(0.0, 1.0);
    final unit = p.unit;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Material(
        color: p.reached ? HsColors.completed : HsColors.warningBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DailyReportScreen())),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(p.reached ? Icons.emoji_events_outlined : Icons.track_changes, color: p.reached ? HsColors.onPastel : HsColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.target <= 0
                        ? 'Meetings assigned today'
                        : (p.reached ? 'Target reached - ${p.counted} $unit today' : '${p.remaining} more $unit needed today'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: HsColors.onPastel),
                  ),
                ),
                if (p.target > 0) Text('${p.counted}/${p.target}', style: const TextStyle(fontWeight: FontWeight.w700, color: HsColors.onPastel)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: frac, minHeight: 7, backgroundColor: Colors.white54),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  '${p.made} made · ${p.connected} connected · ${p.newConnected} new connected',
                  if (p.meetingTarget > 0) 'meetings ${p.meetings}/${p.meetingTarget}${p.meetingsRemaining > 0 ? ' (${p.meetingsRemaining} more)' : ' ✓'}',
                  if (p.lastCall != null) 'last call ${fmtTime(p.lastCall)}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: HsColors.onPastel),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Managers: each caller's daily call target, alert times and "no calls for" alert.
class TargetsScreen extends StatefulWidget {
  const TargetsScreen({super.key});

  @override
  State<TargetsScreen> createState() => _TargetsScreenState();
}

class _TargetsScreenState extends State<TargetsScreen> {
  List<CallerTarget>? _items;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final items = await context.read<SessionController>().repo.callerTargets();
      if (mounted) setState(() {
        _items = items;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Call targets')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
            'Cold callers (Hipersign Cold Caller role) are listed here. Set calls per day and when to alert them: at the alert times they get a big alert with the calls still needed, and during working hours when they make no call for a while (unless a follow-up, meeting or training is going on).',
            style: TextStyle(color: HsColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (_error != null) SyncBanner(error: _error),
          if (items == null && _error == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          if (items != null && items.isEmpty)
            const EmptyState(icon: Icons.person_search, title: 'No callers', message: 'Give someone the "Hipersign Cold Caller" role in ERPNext.'),
          for (final t in items ?? const <CallerTarget>[])
            Card(
              elevation: 0,
              color: HsColors.card,
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(!t.enabled
                    ? 'No target set'
                    : [
                        '${t.dailyTarget} ${t.connectedOnly && t.newOnly ? 'new connected calls' : 'calls'}/day',
                        if (t.meetingTarget > 0) '${t.meetingTarget} meetings/day',
                        if (t.progress != null && t.meetingTarget > 0) 'meetings today ${t.progress!.meetings}/${t.meetingTarget}',
                        if (t.progress != null) 'today ${t.progress!.counted}/${t.progress!.target}',
                        if (t.checkTimes.isNotEmpty) 'alerts ${t.checkTimes}',
                        if (t.idleMinutes > 0) 'idle ${t.idleMinutes} min',
                      ].join(' · ')),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final saved = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => _TargetSheet(t: t),
                  );
                  if (saved == true) _load();
                },
              ),
            ),
        ]),
      ),
    );
  }
}

class _TargetSheet extends StatefulWidget {
  const _TargetSheet({required this.t});
  final CallerTarget t;

  @override
  State<_TargetSheet> createState() => _TargetSheetState();
}

class _TargetSheetState extends State<_TargetSheet> {
  late bool _enabled = widget.t.enabled || widget.t.dailyTarget > 0;
  late final _target = TextEditingController(text: '${widget.t.dailyTarget > 0 ? widget.t.dailyTarget : 70}');
  late Set<String> _times = widget.t.checkTimes.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  late int _idle = widget.t.idleMinutes;
  late TimeOfDay _start = _parse(widget.t.workStart, const TimeOfDay(hour: 9, minute: 30));
  late TimeOfDay _end = _parse(widget.t.workEnd, const TimeOfDay(hour: 18, minute: 0));
  // What counts towards the target: all / connected / new connected calls.
  late String _count = !widget.t.enabled || (widget.t.connectedOnly && widget.t.newOnly)
      ? 'new_connected'
      : (widget.t.connectedOnly ? 'connected' : (widget.t.newOnly ? 'new' : 'all'));
  late final _meetings = TextEditingController(text: widget.t.meetingTarget > 0 ? '${widget.t.meetingTarget}' : '');

  static TimeOfDay _parse(String v, TimeOfDay d) {
    final p = v.split(':');
    if (p.length < 2) return d;
    return TimeOfDay(hour: int.tryParse(p[0]) ?? d.hour, minute: int.tryParse(p[1]) ?? d.minute);
  }

  static String _hm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// "1 h before leaving" etc. from the working-until time.
  String _before(int minutes) {
    final total = _end.hour * 60 + _end.minute - minutes;
    return _hm(TimeOfDay(hour: (total ~/ 60) % 24, minute: total % 60));
  }

  @override
  void dispose() {
    _target.dispose();
    _meetings.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = int.tryParse(_target.text.trim()) ?? 0;
    if (_enabled && n <= 0) return showMissing(context, 'Calls per day missing', 'Enter how many calls they should make each day.');
    final repo = context.read<SessionController>().repo;
    final sorted = _times.toList()..sort();
    final ok = await runWrite(
      context,
      () => repo.saveCallerTarget({
        'user': widget.t.user,
        'enabled': _enabled ? 1 : 0,
        'daily_target': n,
        'check_times': sorted.join(','),
        'idle_minutes': _idle,
        'work_start': _hm(_start),
        'work_end': _hm(_end),
        'count_connected_only': (_count == 'connected' || _count == 'new_connected') ? 1 : 0,
        'count_new_only': (_count == 'new' || _count == 'new_connected') ? 1 : 0,
        'meeting_target': int.tryParse(_meetings.text.trim()) ?? 0,
      }).then((_) => true),
      success: 'Target saved',
    );
    if (ok == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final presets = {'2 h before leaving': _before(120), '1 h before leaving': _before(60), '30 min before leaving': _before(30)};
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(widget.t.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Call target on'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          if (_enabled) ...[
            TextField(controller: _target, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Calls per day')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _count,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Count towards the target'),
              items: const [
                DropdownMenuItem(value: 'new_connected', child: Text('Only new connected calls')),
                DropdownMenuItem(value: 'connected', child: Text('Connected calls (new + follow-up)')),
                DropdownMenuItem(value: 'new', child: Text('New calls (connected or not)')),
                DropdownMenuItem(value: 'all', child: Text('All calls made')),
              ],
              onChanged: (v) => setState(() => _count = v ?? 'new_connected'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _meetings,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Meetings to assign per day (optional)', hintText: 'e.g. 3'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _start, helpText: 'Working from');
                    if (t != null) setState(() => _start = t);
                  },
                  child: Text('From ${_start.format(context)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _end, helpText: 'Leaves at');
                    if (t != null) setState(() => _end = t);
                  },
                  child: Text('Leaves ${_end.format(context)}'),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            const Text('Target alerts at', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final e in presets.entries)
                FilterChip(
                  label: Text('${e.key} (${e.value})'),
                  selected: _times.contains(e.value),
                  onSelected: (on) => setState(() => on ? _times.add(e.value) : _times.remove(e.value)),
                ),
              for (final t in _times.where((t) => !presets.values.contains(t)))
                InputChip(label: Text(t), onDeleted: () => setState(() => _times.remove(t))),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Other time'),
                onPressed: () async {
                  final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 16, minute: 0));
                  if (t != null) setState(() => _times.add(_hm(t)));
                },
              ),
            ]),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              initialValue: const [0, 15, 20, 30, 45, 60, 90].contains(_idle) ? _idle : 30,
              decoration: const InputDecoration(labelText: 'Alert when no calls for'),
              items: [
                for (final m in const [0, 15, 20, 30, 45, 60, 90])
                  DropdownMenuItem(value: m, child: Text(m == 0 ? 'Off' : (m < 60 ? '$m minutes' : '${m ~/ 60} h${m % 60 > 0 ? ' ${m % 60} min' : ''}'))),
              ],
              onChanged: (v) => setState(() => _idle = v ?? 30),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ]),
      ),
    );
  }
}
