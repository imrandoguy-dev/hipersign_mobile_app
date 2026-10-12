import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../core/notifications/reminder_planner.dart';
import '../../core/repository.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/activity_card.dart';
import '../../shared/widgets/common.dart';
import '../activities/activity_detail_screen.dart';

enum CalView { day, week, month }

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalView _view = CalView.day;
  DateTime _selected = dateOnly(DateTime.now());
  CalendarData? _data;
  Map<String, Map<String, int>>? _markers;
  DateTime? _syncedAt;
  ApiException? _error;
  bool _loading = false;
  final _strip = ScrollController();

  Repository get _repo => context.read<SessionController>().repo;

  @override
  void initState() {
    super.initState();
    refreshTick.addListener(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _centerStrip();
      planLocalReminders(_repo);
    });
  }

  @override
  void dispose() {
    refreshTick.removeListener(_load);
    _strip.dispose();
    super.dispose();
  }

  (DateTime, DateTime) get _range => switch (_view) {
        CalView.day => (_selected, _selected),
        CalView.week => (
            _selected.subtract(Duration(days: _selected.weekday - 1)),
            _selected.subtract(Duration(days: _selected.weekday - 1)).add(const Duration(days: 6))
          ),
        CalView.month => (DateTime(_selected.year, _selected.month, 1), DateTime(_selected.year, _selected.month + 1, 0)),
      };

  Future<void> _load() async {
    if (!mounted) return;
    final repo = _repo;
    if (_view == CalView.month) {
      final cached = repo.cachedMonthMarkers(_selected);
      final entry = repo.cached('month:${DateFormat('yyyy-MM').format(_selected)}');
      setState(() {
        _markers = cached ?? _markers;
        _syncedAt = entry?.syncedAt ?? _syncedAt;
        _loading = true;
      });
      try {
        final m = await repo.monthMarkers(_selected);
        if (!mounted) return;
        setState(() {
          _markers = m;
          _syncedAt = DateTime.now();
          _error = null;
        });
      } on ApiException catch (e) {
        if (mounted) setState(() => _error = e);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }
    final (start, end) = _range;
    final cached = repo.cachedCalendar(start, end);
    final entry = repo.cached(Repository.calendarKey(start, end));
    setState(() {
      _data = cached;
      _syncedAt = entry?.syncedAt;
      _loading = true;
    });
    try {
      final d = await repo.calendar(start, end);
      if (!mounted) return;
      setState(() {
        _data = d;
        _syncedAt = DateTime.now();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(DateTime d, {CalView? view}) {
    setState(() {
      _selected = dateOnly(d);
      if (view != null) _view = view;
      _data = null;
    });
    _load();
  }

  void _centerStrip() {
    if (!_strip.hasClients) return;
    final index = _selected.difference(dateOnly(DateTime.now())).inDays + 30;
    _strip.jumpTo((index * 60.0 - 140).clamp(0.0, _strip.position.maxScrollExtent).toDouble());
  }

  Future<void> _openActivity(Activity a) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: a.id)));
    _load();
  }

  void _logContact(Activity a, String channel) {
    _repo.logContact(a.id, channel).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_view) {
      CalView.day => DateFormat('EEEE, d MMMM').format(_selected),
      CalView.week => 'Week of ${DateFormat('d MMM').format(_range.$1)}',
      CalView.month => DateFormat('MMMM yyyy').format(_selected),
    };
    final isToday = _selected == dateOnly(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (!isToday)
            TextButton(onPressed: () => _select(DateTime.now()), child: const Text('Today')),
          IconButton(
            tooltip: 'Previous',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _select(switch (_view) {
              CalView.day => _selected.subtract(const Duration(days: 1)),
              CalView.week => _selected.subtract(const Duration(days: 7)),
              CalView.month => DateTime(_selected.year, _selected.month - 1, 1),
            }),
          ),
          IconButton(
            tooltip: 'Next',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _select(switch (_view) {
              CalView.day => _selected.add(const Duration(days: 1)),
              CalView.week => _selected.add(const Duration(days: 7)),
              CalView.month => DateTime(_selected.year, _selected.month + 1, 1),
            }),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await context.read<SessionController>().refreshProfile();
          await _load();
          planLocalReminders(_repo);
        },
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SegmentedButton<CalView>(
                segments: const [
                  ButtonSegment(value: CalView.day, label: Text('Day')),
                  ButtonSegment(value: CalView.week, label: Text('Week')),
                  ButtonSegment(value: CalView.month, label: Text('Month')),
                ],
                selected: {_view},
                onSelectionChanged: (s) {
                  setState(() {
                    _view = s.first;
                    _data = null;
                  });
                  _load();
                },
              ),
            ),
          ),
          if (_view == CalView.day) SliverToBoxAdapter(child: _dateStrip()),
          SliverToBoxAdapter(child: SyncBanner(syncedAt: _syncedAt, error: _error)),
          if (_loading && _data == null && _view != CalView.month)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))),
          ..._body(),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ]),
      ),
    );
  }

  Widget _dateStrip() {
    final today = dateOnly(DateTime.now());
    return SizedBox(
      height: 76,
      child: ListView.builder(
        controller: _strip,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: 91,
        itemBuilder: (_, i) {
          final d = today.add(Duration(days: i - 30));
          final selected = d == _selected;
          final isToday = d == today;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Semantics(
              selected: selected,
              label: DateFormat('EEEE d MMMM').format(d),
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _select(d),
                child: Container(
                  width: 52,
                  decoration: BoxDecoration(
                    color: selected ? HsColors.accent : HsColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: isToday && !selected ? Border.all(color: HsColors.accent) : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(DateFormat('EEE').format(d),
                        style: TextStyle(fontSize: 12, color: selected ? HsColors.onAccent : HsColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text('${d.day}',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700, color: selected ? HsColors.onAccent : HsColors.textPrimary)),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _cards(List<Activity> list, {ActivityState? force}) => list
      .map((a) => ActivityCard(
            activity: a,
            stateOverride: force,
            onTap: () => _openActivity(a),
            onContact: (c) => _logContact(a, c),
          ))
      .toList();

  List<Widget> _body() {
    if (_view == CalView.month) return [SliverToBoxAdapter(child: _monthGrid())];
    final d = _data;
    if (d == null) return const [];

    if (_view == CalView.week) {
      final (start, _) = _range;
      final widgets = <Widget>[];
      for (var i = 0; i < 7; i++) {
        final day = start.add(Duration(days: i));
        final items = d.items.where((a) => a.start != null && dateOnly(a.start!) == day).toList();
        widgets.add(SliverToBoxAdapter(
          child: InkWell(
            onTap: () => _select(day, view: CalView.day),
            child: SectionHeader(DateFormat('EEEE d MMM').format(day), count: items.length),
          ),
        ));
        if (items.isEmpty) {
          widgets.add(const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Nothing scheduled', style: TextStyle(color: HsColors.textSecondary)),
            ),
          ));
        } else {
          widgets.add(SliverList(delegate: SliverChildListDelegate(_cards(items))));
        }
      }
      return widgets;
    }

    // Day view: the day's assigned work first, then pending work carried over.
    final scheduled = d.items;
    final pending = [...d.overdue, ...d.unscheduled];
    if (scheduled.isEmpty && pending.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: EmptyState(
            icon: Icons.event_available,
            title: 'Nothing scheduled',
            message: 'Use the + button to add a follow-up or meeting.',
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(child: SectionHeader('Assigned work', count: scheduled.length, color: HsColors.active)),
      if (scheduled.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('No activities on this day.', style: TextStyle(color: HsColors.textSecondary)),
          ),
        )
      else
        SliverList(delegate: SliverChildListDelegate(_cards(scheduled))),
      if (pending.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader('Pending', count: pending.length, color: HsColors.pending)),
        SliverList(delegate: SliverChildListDelegate(_cards(pending, force: ActivityState.pending))),
      ],
    ];
  }

  Widget _monthGrid() {
    final first = DateTime(_selected.year, _selected.month, 1);
    final daysInMonth = DateTime(_selected.year, _selected.month + 1, 0).day;
    final leading = first.weekday - 1; // Monday first
    final cells = leading + daysInMonth;
    final today = dateOnly(DateTime.now());
    if (_loading && _markers == null) {
      return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(children: [
        Row(
          children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
              .map((d) => Expanded(
                    child: Center(child: Text(d, style: const TextStyle(color: HsColors.textSecondary, fontSize: 12))),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.8),
          itemCount: (cells / 7).ceil() * 7,
          itemBuilder: (_, i) {
            final dayNum = i - leading + 1;
            if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox();
            final day = DateTime(_selected.year, _selected.month, dayNum);
            final m = _markers?[ymd(day)] ?? const {};
            final isToday = day == today;
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _select(day, view: CalView.day),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: HsColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: isToday ? Border.all(color: HsColors.accent) : null,
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('$dayNum', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 2,
                    children: [
                      for (final s in ['active', 'pending', 'rescheduled', 'completed'])
                        if ((m[s] ?? 0) > 0)
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(color: ActivityStateStyle.parse(s).color, shape: BoxShape.circle),
                          ),
                    ],
                  ),
                ]),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 14, runSpacing: 6, children: [
          for (final s in [ActivityState.active, ActivityState.pending, ActivityState.rescheduled, ActivityState.completed])
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(s.label, style: const TextStyle(fontSize: 12, color: HsColors.textSecondary)),
            ]),
        ]),
      ]),
    );
  }
}
