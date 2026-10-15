import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';

/// Countdown banner of a multi-day trial: "Day 3 of 7 · 4 days left" with a progress bar.
/// "Thu 16 Oct 2:00 PM, Fri 17 Oct 11:30 AM" - the (not cancelled) sessions in time order.
String trainingDays(List<TrialSession> sessions) {
  final live = sessions.where((s) => s.status != 'Cancelled' && s.start != null).toList()
    ..sort((a, b) => a.start!.compareTo(b.start!));
  return live.map((s) => fmtDayTime(s.start).replaceFirst(',', '')).join(', ');
}

class TrialCountdown extends StatelessWidget {
  const TrialCountdown({super.key, required this.trial, this.compact = false});

  final TrialPeriod trial;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = trial;
    final progress = switch (t.phase) {
      'ended' => 1.0,
      'upcoming' => 0.0,
      _ => t.days == 0 ? 0.0 : (t.dayNo / t.days).clamp(0.0, 1.0),
    };
    final color = switch (t.phase) {
      'ended' => HsColors.textSecondary,
      'upcoming' => HsColors.blue,
      _ => t.daysLeft <= 1 ? HsColors.danger : HsColors.navy,
    };
    final text = Row(children: [
      Icon(t.phase == 'ended' ? Icons.flag_outlined : Icons.timelapse, size: 16, color: color),
      const SizedBox(width: 6),
      Flexible(
        child: Text(t.countdown, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: compact ? 12.5 : 14)),
      ),
    ]);
    if (compact) return text;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: HsColors.card, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        text,
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: progress, minHeight: 8, color: color, backgroundColor: HsColors.cardHigh),
        ),
        const SizedBox(height: 8),
        Text(
          '${fmtDay(t.startDate)} → ${fmtDay(t.endDate)} · ${t.sessionsDone} of ${t.sessions.where((s) => s.status != 'Cancelled').length} sessions done',
          style: const TextStyle(fontSize: 12.5, color: HsColors.textSecondary),
        ),
      ]),
    );
  }
}

/// Trial length chooser: 1 / 3 / 5 / 7 days or any other number.
class TrialDaysPicker extends StatelessWidget {
  const TrialDaysPicker({super.key, required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  static Future<int?> askNumber(BuildContext context, int current) async {
    final c = TextEditingController(text: '$current');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trial length'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Number of days', suffixText: 'days'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true) return null;
    final n = int.tryParse(c.text.trim());
    return (n == null || n < 1 || n > 60) ? null : n;
  }

  @override
  Widget build(BuildContext context) {
    const presets = [1, 3, 5, 7];
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final d in presets)
        ChoiceChip(label: Text(d == 1 ? '1 day' : '$d days'), selected: days == d, onSelected: (_) => onChanged(d)),
      ChoiceChip(
        label: Text(presets.contains(days) ? 'Other…' : '$days days'),
        selected: !presets.contains(days),
        onSelected: (_) async {
          final n = await askNumber(context, days);
          if (n != null) onChanged(n);
        },
      ),
    ]);
  }
}
