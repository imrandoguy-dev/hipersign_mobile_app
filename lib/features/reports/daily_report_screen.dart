import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/team.dart';
import '../../shared/widgets/common.dart';
import '../activities/activity_detail_screen.dart';
import '../calls/calls_screen.dart';
import '../development/development_screen.dart';

String _dayLabel(DateTime d) {
  final n = DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final x = DateTime(d.year, d.month, d.day);
  if (x == today) return 'Today';
  if (x == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat('EEE d MMM').format(d);
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.day, required this.onChanged});
  final DateTime day;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    final isToday = DateTime(day.year, day.month, day.day) == DateTime(n.year, n.month, n.day);
    return Row(children: [
      IconButton(onPressed: () => onChanged(day.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left)),
      Expanded(
        child: TextButton(
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: day, firstDate: DateTime(2024), lastDate: n);
            if (d != null) onChanged(d);
          },
          child: Text(_dayLabel(day), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
      IconButton(onPressed: isToday ? null : () => onChanged(day.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right)),
    ]);
  }
}

/// One person's day: what was due - done and not done - and calls. Opens on today.
class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key, this.user, this.name, this.day});
  final String? user; // another person (managers); null = me
  final String? name;
  final DateTime? day;

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  late DateTime _day = widget.day ?? DateTime.now();
  DailyReport? _r;
  ApiException? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await context.read<SessionController>().repo.dailyReport(_day, user: widget.user);
      if (mounted) setState(() {
        _r = r;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(ReportItem i) {
    if (i.refName == null) return;
    final Widget? screen = switch (i.refDoctype) {
      'CRM Task' => ActivityDetailScreen(activityId: i.refName!),
      'Team Task' => DevTaskScreen(taskId: i.refName!, kind: 'team'),
      'Development Task' => DevTaskScreen(taskId: i.refName!),
      _ => null,
    };
    if (screen != null) Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final notDone = r?.items.where((i) => i.open).toList() ?? [];
    final done = r?.items.where((i) => !i.open).toList() ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(widget.name == null ? 'My daily report' : '${widget.name} - daily report')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          _DayBar(day: _day, onChanged: (d) {
            setState(() => _day = d);
            _load();
          }),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) SyncBanner(error: _error),
          if (r != null) ...[
            Row(children: [
              _Stat(label: 'Done', value: '${r.done}', color: HsColors.completed),
              const SizedBox(width: 8),
              _Stat(label: 'Not done', value: '${r.notDone}', color: r.notDone > 0 ? HsColors.overdue : HsColors.card),
              const SizedBox(width: 8),
              _Stat(
                label: r.callTarget != null ? 'Calls / target' : 'Calls',
                value: r.callTarget != null ? '${r.callsMade}/${r.callTarget}' : '${r.callsMade}',
                color: HsColors.active,
              ),
            ]),
            if (r.callsMade > 0 || r.meetingsAssigned > 0 || (r.meetingTarget ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [
                    if (r.callsMade > 0) '${r.callsConnected} of ${r.callsMade} calls connected · ${r.newConnected} new connected',
                    if (r.newNotReached > 0) 'New leads not reached: ${r.newNotReached}',
                    if (r.meetingsAssigned > 0 || (r.meetingTarget ?? 0) > 0)
                      'Meetings assigned: ${r.meetingsAssigned}${(r.meetingTarget ?? 0) > 0 ? ' of ${r.meetingTarget}' : ''}',
                  ].join('\n'),
                  style: const TextStyle(color: HsColors.textSecondary),
                ),
              ),
            if (r.newNotReached > 0 && widget.user == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const CallsScreen(initialFilter: 'new_not_reached'))),
                  icon: const Icon(Icons.phone_missed),
                  label: Text('Call back ${r.newNotReached} new lead${r.newNotReached == 1 ? '' : 's'} not reached'),
                ),
              ),
            if (r.items.isEmpty)
              const EmptyState(icon: Icons.event_available, title: 'Nothing was due', message: 'No follow-ups, meetings, trainings or tasks for this day.'),
            if (notDone.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Not done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: HsColors.danger)),
              for (final i in notDone) _ItemRow(item: i, onTap: () => _open(i)),
            ],
            if (done.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Done / closed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              for (final i in done) _ItemRow(item: i, onTap: () => _open(i)),
            ],
          ],
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: HsColors.onPastel)),
            Text(label, style: const TextStyle(fontSize: 12, color: HsColors.onPastel)),
          ]),
        ),
      );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onTap});
  final ReportItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i = item;
    final color = i.done ? const Color(0xFF2E7D32) : (i.open ? HsColors.danger : HsColors.textSecondary);
    return Card(
      elevation: 0,
      color: HsColors.card,
      margin: const EdgeInsets.only(top: 6),
      child: ListTile(
        onTap: onTap,
        leading: Icon(i.done ? Icons.check_circle : (i.open ? Icons.radio_button_unchecked : Icons.remove_circle_outline), color: color),
        title: Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text([i.kind, if (i.party != null && i.party!.isNotEmpty) i.party!, if (i.at != null && i.at!.isNotEmpty) i.at!].join(' · ')),
        trailing: SizedBox(
          width: 92,
          child: Text(i.result, textAlign: TextAlign.end, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// Everyone's day at a glance (managers / HR): tap a person for their report.
class TeamReportScreen extends StatefulWidget {
  const TeamReportScreen({super.key});

  @override
  State<TeamReportScreen> createState() => _TeamReportScreenState();
}

class _TeamReportScreenState extends State<TeamReportScreen> {
  DateTime _day = DateTime.now();
  List<DailyReport>? _items;
  ApiException? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await context.read<SessionController>().repo.teamReport(_day);
      if (mounted) setState(() {
        _items = items;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Team daily report')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          _DayBar(day: _day, onChanged: (d) {
            setState(() => _day = d);
            _load();
          }),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) SyncBanner(error: _error),
          if (items != null && items.isEmpty) const EmptyState(icon: Icons.groups_outlined, title: 'No work or calls this day'),
          if (items != null && items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${items.length} people · ${items.fold<int>(0, (a, r) => a + r.done)} done · ${items.fold<int>(0, (a, r) => a + r.notDone)} not done · ${items.fold<int>(0, (a, r) => a + r.callsMade)} calls',
                style: const TextStyle(color: HsColors.textSecondary),
              ),
            ),
          for (final r in items ?? const <DailyReport>[])
            Card(
              elevation: 0,
              color: r.notDone > 0 ? HsColors.overdue : HsColors.card,
              margin: const EdgeInsets.only(top: 6),
              child: ListTile(
                title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  '${r.done} done',
                  '${r.notDone} not done',
                  if (r.callsMade > 0 || r.callTarget != null) '${r.callsMade}${r.callTarget != null ? '/${r.callTarget}' : ''} calls (${r.newConnected} new connected)',
                  if (r.newNotReached > 0) '${r.newNotReached} new not reached',
                  if (r.meetingsAssigned > 0 || (r.meetingTarget ?? 0) > 0) '${r.meetingsAssigned}${(r.meetingTarget ?? 0) > 0 ? '/${r.meetingTarget}' : ''} meetings',
                ].join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DailyReportScreen(user: r.user, name: r.name, day: _day))),
              ),
            ),
        ]),
      ),
    );
  }
}
