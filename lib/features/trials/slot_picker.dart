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
  const SlotPicker({super.key, required this.bookingType, required this.onPick, this.selectedId, this.refreshKey = 0});

  final String bookingType;
  final String? selectedId;
  final ValueChanged<TrainerSlot> onPick;
  final int refreshKey;

  @override
  State<SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<SlotPicker> {
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

  @override
  Widget build(BuildContext context) {
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
            initialValue: _trainer,
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
          message: 'Trainers have no open slots in the next $_days days.',
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
