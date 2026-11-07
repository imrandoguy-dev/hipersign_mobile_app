import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../shared/models/team.dart';

String hm(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

const _meeting = Color(0xFF5B6CFF);
const _followup = Color(0xFFF4A340);
const _trial = Color(0xFF9B59B6);
const _connected = Color(0xFF2E9E5B);
const _missed = Color(0xFF9AA3AE);
const _freeColor = Color(0xFFFFD9D6);

Color _blockColor(String kind) => switch (kind) {
      'meeting' => _meeting,
      'trial' => _trial,
      _ => _followup,
    };

/// The day as a line: free gaps (light red), meetings / follow-ups / trainings (blocks),
/// calls (ticks: green connected, grey not), tasks finished (dots).
class DayTimelineBar extends StatelessWidget {
  const DayTimelineBar({super.key, required this.t, this.height = 34, this.showHours = true});
  final DayTimeline t;
  final double height;
  final bool showHours;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(height: height, child: CustomPaint(painter: _BarPainter(t))),
      if (showHours) SizedBox(height: 16, child: CustomPaint(painter: _HoursPainter(t, Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey))),
    ]);
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.t);
  final DayTimeline t;

  @override
  void paint(Canvas canvas, Size size) {
    final span = (t.end - t.start).clamp(1, 1440);
    double x(int m) => ((m - t.start) / span * size.width).clamp(0, size.width).toDouble();
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEEF1F5));
    // Outside work hours: hatched darker.
    final off = Paint()..color = const Color(0xFFDDE2E8);
    if (t.workStart > t.start) canvas.drawRect(Rect.fromLTRB(0, 0, x(t.workStart), size.height), off);
    if (t.workEnd < t.end) canvas.drawRect(Rect.fromLTRB(x(t.workEnd), 0, size.width, size.height), off);
    // Not happened yet (today).
    if (t.until < t.end) {
      canvas.drawRect(Rect.fromLTRB(x(t.until), 0, size.width, size.height), Paint()..color = Colors.white.withValues(alpha: 0.55));
    }
    for (final f in t.free) {
      canvas.drawRect(Rect.fromLTRB(x(f.from), 0, x(f.to), size.height), Paint()..color = _freeColor);
    }
    for (final b in t.blocks) {
      final rect = Rect.fromLTRB(x(b.from), size.height * 0.18, x(b.to).clamp(x(b.from) + 3, size.width), size.height * 0.82);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), Paint()..color = _blockColor(b.kind));
    }
    for (final c in t.calls) {
      final cx = x(c.at);
      final w = (c.seconds / 60 / span * size.width).clamp(2.0, size.width).toDouble();
      canvas.drawRect(Rect.fromLTWH(cx, 0, w, size.height * (c.connected ? 1 : 0.55)),
          Paint()..color = c.connected ? _connected : _missed);
    }
    for (final m in t.marks) {
      canvas.drawCircle(Offset(x(m.$1), size.height - 5), 4, Paint()..color = HsColors.navy);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.t != t;
}

class _HoursPainter extends CustomPainter {
  _HoursPainter(this.t, this.color);
  final DayTimeline t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final span = (t.end - t.start).clamp(1, 1440);
    final step = span > 600 ? 120 : 60;
    for (var m = ((t.start + 59) ~/ 60) * 60; m <= t.end; m += step) {
      final h = m ~/ 60;
      final label = h == 0 ? '12a' : (h < 12 ? '${h}a' : (h == 12 ? '12p' : '${h - 12}p'));
      final tp = TextPainter(text: TextSpan(text: label, style: TextStyle(fontSize: 10, color: color)), textDirection: TextDirection.ltr)..layout();
      final x = ((m - t.start) / span * size.width) - tp.width / 2;
      tp.paint(canvas, Offset(x.clamp(0, size.width - tp.width).toDouble(), 2));
    }
  }

  @override
  bool shouldRepaint(covariant _HoursPainter old) => old.t != t;
}

/// Full card for one person's report: the line, totals, legend, and the free / busy list.
class DayTimelineCard extends StatefulWidget {
  const DayTimelineCard({super.key, required this.t});
  final DayTimeline t;

  @override
  State<DayTimelineCard> createState() => _DayTimelineCardState();
}

class _DayTimelineCardState extends State<DayTimelineCard> {
  bool _open = false;

  Widget _legend(Color c, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11.5)),
      ]);

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final connected = t.calls.where((c) => c.connected).length;
    // Busy and free in time order, for the list.
    final rows = <(int, Widget)>[
      for (final f in t.free)
        (f.from, _row(Icons.hourglass_empty, HsColors.danger, '${f.fromText} - ${f.toText}', 'Free · ${hm(f.minutes)}')),
      for (final b in t.blocks)
        (b.from, _row(Icons.event, _blockColor(b.kind), '${b.fromText} - ${b.toText}', b.label + (b.done ? ' ✓' : ''))),
      ..._callRuns(t),
      for (final m in t.marks) (m.$1, _row(Icons.task_alt, HsColors.navy, m.$2, m.$3)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return Card(
      elevation: 0,
      color: HsColors.card,
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: Text('Day timeline', style: TextStyle(fontWeight: FontWeight.w700))),
            Text('Busy ${hm(t.busyMinutes)} · Free ${hm(t.freeMinutes)}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Text(
            t.fromCheckIn
                ? 'Checked in ${t.checkIn}${t.checkOut != null ? ' · out ${t.checkOut}' : ''} · at work ${hm(t.atWorkMinutes)}'
                : 'No check-in · using work hours (${hm(t.atWorkMinutes)})',
            style: TextStyle(fontSize: 12.5, color: t.fromCheckIn ? HsColors.navy : HsColors.textSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          DayTimelineBar(t: t),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 4, children: [
            _legend(_freeColor, 'Free'),
            if (t.blocks.any((b) => b.kind == 'meeting')) _legend(_meeting, 'Meeting'),
            if (t.blocks.any((b) => b.kind == 'followup')) _legend(_followup, 'Follow-up'),
            if (t.blocks.any((b) => b.kind == 'trial')) _legend(_trial, 'Training'),
            if (t.calls.isNotEmpty) _legend(_connected, 'Call connected'),
            if (t.calls.any((c) => !c.connected)) _legend(_missed, 'Not connected'),
            if (t.marks.isNotEmpty) _legend(HsColors.navy, 'Task done'),
          ]),
          if (t.calls.isNotEmpty || t.longestFree > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                [
                  if (t.callsSummary != null) t.callsSummary!
                  else if (t.calls.isNotEmpty) '${t.calls.length} calls ($connected connected)',
                  if (t.longestFree > 0) 'Longest free time: ${hm(t.longestFree)}',
                ].join('\n'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          if (rows.isNotEmpty)
            TextButton.icon(
              style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero),
              onPressed: () => setState(() => _open = !_open),
              icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
              label: Text(_open ? 'Hide times' : 'Show all times (free and busy)'),
            ),
          if (_open) ...[for (final r in rows) r.$2],
          if (t.empty && t.free.isEmpty)
            const Text('Nothing on the timeline for this day.', style: TextStyle(color: HsColors.textSecondary)),
        ]),
      ),
    );
  }

  /// Calls close together (under the free-time gap) shown as one "calling" row.
  List<(int, Widget)> _callRuns(DayTimeline t) {
    final out = <(int, Widget)>[];
    var i = 0;
    while (i < t.calls.length) {
      var j = i;
      while (j + 1 < t.calls.length && t.calls[j + 1].at - (t.calls[j].at + (t.calls[j].seconds / 60).ceil()) < t.minGap) {
        j++;
      }
      final run = t.calls.sublist(i, j + 1);
      final ok = run.where((c) => c.connected).length;
      final when = run.length == 1 ? run.first.atText : '${run.first.atText} - ${run.last.atText}';
      final what = run.length == 1
          ? '${run.first.incoming ? 'Incoming' : 'Call'}${run.first.who.isNotEmpty ? ' · ${run.first.who}' : ''} · ${run.first.connected ? 'connected ${hm((run.first.seconds / 60).ceil())}' : 'not connected'}'
          : 'Calling · ${run.length} calls, $ok connected';
      out.add((run.first.at, _row(Icons.call, _connected, when, what)));
      i = j + 1;
    }
    return out;
  }

  Widget _row(IconData icon, Color color, String when, String what) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          SizedBox(width: 128, child: Text(when, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
          Expanded(child: Text(what, style: const TextStyle(fontSize: 12.5))),
        ]),
      );
}
