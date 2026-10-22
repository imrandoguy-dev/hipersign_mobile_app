import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';

/// Lists free trainer time (advisory: the server re-checks when booking).
class SlotPicker extends StatefulWidget {
  const SlotPicker({
    super.key,
    required this.bookingType,
    required this.onPick,
    this.selectedId,
    this.refreshKey = 0,
    this.initialTrainer,
    this.initialStart,
    this.initialEnd,
  });

  final String bookingType;
  final String? selectedId;
  final ValueChanged<TrainerSlot> onPick;
  final int refreshKey;
  final String? initialTrainer; // e.g. the session's trainer when moving it
  final DateTime? initialStart; // pre-fills the exact-time fields
  final DateTime? initialEnd;

  @override
  State<SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<SlotPicker> {
  bool _exact = true; // pick an exact start and end time (default) or browse free times
  DateTime _from = DateTime.now();
  int _days = 14;
  String? _trainer;
  List<Map<String, String>> _trainers = [];
  List<TrainerSlot> _slots = [];
  bool _loading = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _trainer = widget.initialTrainer;
    final a = widget.initialStart, b = widget.initialEnd;
    if (a != null) {
      final now = DateTime.now();
      final day = DateTime(a.year, a.month, a.day);
      _day = day.isBefore(DateTime(now.year, now.month, now.day)) ? DateTime(now.year, now.month, now.day) : day;
      _startT = TimeOfDay.fromDateTime(a);
      if (b != null) _endT = TimeOfDay.fromDateTime(b);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final t = await context.read<SessionController>().repo.trainers();
        if (mounted) setState(() => _trainers = t);
      } catch (_) {}
      _load();
    });
  }

  @override
  void didUpdateWidget(covariant SlotPicker old) {
    super.didUpdateWidget(old);
    if (old.bookingType != widget.bookingType || old.refreshKey != widget.refreshKey) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await context.read<SessionController>().repo.slots(
            _from,
            _from.add(Duration(days: _days)),
            trainer: _trainer,
            bookingType: widget.bookingType,
          );
      if (mounted) setState(() {
        _slots = s;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------- exact time
  late DateTime _day = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  TimeOfDay? _startT;
  TimeOfDay? _endT;
  bool _checking = false;
  String? _exactError;
  TrainerSlot? _exactSlot;

  DateTime _at(TimeOfDay t) => DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);

  String _dur(int m) => m < 60 ? '$m min' : (m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60} min');

  Future<void> _checkExact() async {
    setState(() {
      _exactError = null;
      _exactSlot = null;
    });
    if (_trainer == null) return setState(() => _exactError = 'Choose the trainer first.');
    if (_startT == null || _endT == null) return setState(() => _exactError = 'Choose the start and end time.');
    final start = _at(_startT!), end = _at(_endT!);
    if (!end.isAfter(start)) return setState(() => _exactError = 'The end time must be after the start time.');
    if (start.isBefore(DateTime.now())) return setState(() => _exactError = 'This time is in the past.');
    setState(() => _checking = true);
    try {
      final slot = await context.read<SessionController>().repo.checkTrainerTime(_trainer!, start, end);
      if (!mounted) return;
      setState(() => _exactSlot = slot);
      widget.onPick(slot);
    } on ApiException catch (e) {
      if (mounted) setState(() => _exactError = e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Widget _exactPicker() {
    final mins = (_startT != null && _endT != null) ? _at(_endT!).difference(_at(_startT!)).inMinutes : null;
    final picked = _exactSlot != null && widget.selectedId == _exactSlot!.id;
    void changed() => setState(() {
          _exactSlot = null;
          _exactError = null;
        });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String?>(
        key: ValueKey('exact-trainers-${_trainers.length}'),
        initialValue: _trainers.any((t) => t['id'] == _trainer) ? _trainer : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Trainer'),
        items: [
          for (final t in _trainers) DropdownMenuItem<String?>(value: t['id'], child: Text(t['name'] ?? '', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          _trainer = v;
          changed();
        },
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        icon: const Icon(Icons.event),
        label: Text(DateFormat('EEEE d MMM').format(_day)),
        onPressed: () async {
          final now = DateTime.now();
          final d = await showDatePicker(
            context: context,
            initialDate: _day,
            firstDate: DateTime(now.year, now.month, now.day),
            lastDate: now.add(const Duration(days: 180)),
          );
          if (d != null) {
            _day = d;
            changed();
          }
        },
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.play_arrow_outlined),
            label: Text(_startT == null ? 'Start time' : 'From ${_startT!.format(context)}'),
            onPressed: () async {
              final t = await showTimePicker(context: context, initialTime: _startT ?? const TimeOfDay(hour: 10, minute: 0), helpText: 'Start time');
              if (t != null) {
                final keep = mins != null && mins > 0 ? mins : 60;
                _startT = t;
                final e = _at(t).add(Duration(minutes: keep));
                _endT = TimeOfDay(hour: e.hour, minute: e.minute);
                changed();
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.stop_outlined),
            label: Text(_endT == null ? 'End time' : 'To ${_endT!.format(context)}'),
            onPressed: () async {
              final t = await showTimePicker(context: context, initialTime: _endT ?? const TimeOfDay(hour: 11, minute: 0), helpText: 'End time');
              if (t != null) {
                _endT = t;
                changed();
              }
            },
          ),
        ),
      ]),
      if (_startT != null) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final m in const [30, 45, 60, 75, 90, 120])
            ChoiceChip(
              label: Text(_dur(m)),
              selected: mins == m,
              onSelected: (_) {
                final e = _at(_startT!).add(Duration(minutes: m));
                _endT = TimeOfDay(hour: e.hour, minute: e.minute);
                changed();
              },
            ),
        ]),
      ],
      const SizedBox(height: 10),
      FilledButton.tonalIcon(
        icon: _checking
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.check),
        label: Text(mins != null && mins > 0 ? 'Use this time (${_dur(mins)})' : 'Use this time'),
        onPressed: _checking ? null : _checkExact,
      ),
      if (_exactError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_exactError!, style: const TextStyle(color: HsColors.danger, fontWeight: FontWeight.w600)),
        ),
      if (picked)
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: HsColors.active, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_exactSlot!.trainerName} is free · ${fmtDayTime(_exactSlot!.start)} - ${fmtTime(_exactSlot!.end)}',
                style: const TextStyle(fontWeight: FontWeight.w700, color: HsColors.onPastel)),
            if (_exactSlot!.note != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Note: ${_exactSlot!.note}', style: const TextStyle(color: HsColors.onPastel)),
              ),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('Exact time'), icon: Icon(Icons.schedule)),
          ButtonSegment(value: false, label: Text('Free times'), icon: Icon(Icons.view_agenda_outlined)),
        ],
        selected: {_exact},
        onSelectionChanged: (s) => setState(() => _exact = s.first),
      ),
      const SizedBox(height: 12),
      if (_exact) _exactPicker() else _freeTimes(),
    ]);
  }

  Widget _freeTimes() {
    final byDay = <String, List<TrainerSlot>>{};
    for (final s in _slots) {
      byDay.putIfAbsent(DateFormat('EEEE d MMM').format(s.start), () => []).add(s);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text('From ${DateFormat('d MMM').format(_from)}'),
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _from,
                firstDate: DateTime(now.year, now.month, now.day),
                lastDate: now.add(const Duration(days: 180)),
              );
              if (d != null) {
                setState(() => _from = d);
                _load();
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String?>(
            key: ValueKey('free-trainers-${_trainers.length}'),
            initialValue: _trainers.any((t) => t['id'] == _trainer) ? _trainer : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Trainer', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any trainer')),
              for (final t in _trainers) DropdownMenuItem<String?>(value: t['id'], child: Text(t['name'] ?? '', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              setState(() => _trainer = v);
              _load();
            },
          ),
        ),
      ]),
      const SizedBox(height: 10),
      if (_error != null) SyncBanner(error: _error),
      if (_loading) const LinearProgressIndicator(),
      if (!_loading && _slots.isEmpty)
        EmptyState(
          icon: Icons.event_busy,
          title: 'No free trainer time',
          message: 'No free times in the next $_days days. Use "Exact time" to pick any time.',
          action: TextButton(
            onPressed: () {
              setState(() => _days += 14);
              _load();
            },
            child: const Text('Look further ahead'),
          ),
        ),
      for (final entry in byDay.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in entry.value)
            ChoiceChip(
              selected: widget.selectedId == s.id,
              selectedColor: HsColors.active,
              label: Text('${fmtTime(s.start)} - ${fmtTime(s.end)}  ${s.trainerName}',
                  style: TextStyle(color: widget.selectedId == s.id ? HsColors.onPastel : HsColors.textPrimary)),
              onSelected: (_) => widget.onPick(s),
            ),
        ]),
      ],
    ]);
  }
}
