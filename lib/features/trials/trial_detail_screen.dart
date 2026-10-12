import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/contact_actions.dart';
import '../activities/activity_detail_screen.dart';
import 'slot_picker.dart';

class TrialDetailScreen extends StatefulWidget {
  const TrialDetailScreen({super.key, required this.bookingId});
  final String bookingId;

  @override
  State<TrialDetailScreen> createState() => _TrialDetailScreenState();
}

class _TrialDetailScreenState extends State<TrialDetailScreen> {
  Booking? _b;
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final b = await context.read<SessionController>().repo.booking(widget.bookingId);
      if (mounted) setState(() {
        _b = b;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _askText(String title, String label, String confirm) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, maxLines: 3, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirm)),
        ],
      ),
    );
    if (ok != true) return null;
    return c.text.trim();
  }

  Future<void> _cancel() async {
    final reason = await _askText('Cancel this booking?', 'Reason (optional)', 'Cancel booking');
    if (reason == null || !mounted) return;
    final repo = context.read<SessionController>().repo;
    final b = await runWrite(context, () => repo.cancelBooking(_b!.id, reason.isEmpty ? null : reason), success: 'Booking cancelled');
    if (b != null) {
      bumpRefresh();
      setState(() => _b = b);
    }
  }

  Future<void> _complete() async {
    final notes = await _askText('Mark trial as completed', 'How did it go? (optional)', 'Complete');
    if (notes == null || !mounted) return;
    final repo = context.read<SessionController>().repo;
    final b = await runWrite(context, () => repo.completeBooking(_b!.id, notes.isEmpty ? null : notes), success: 'Trial completed');
    if (b != null) {
      bumpRefresh();
      setState(() => _b = b);
    }
  }

  Future<void> _reschedule() async {
    final b = _b!;
    TrainerSlot? picked;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (_, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            const Text('Pick a new time', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SlotPicker(bookingType: b.bookingType, selectedId: picked?.id, onPick: (s) => setSheet(() => picked = s)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: picked == null ? null : () => Navigator.pop(ctx, true),
              child: Text(picked == null ? 'Pick a slot' : 'Move to ${fmtDayTime(picked!.start)}'),
            ),
          ]),
        ),
      ),
    );
    if (ok != true || picked == null || !mounted) return;
    final repo = context.read<SessionController>().repo;
    final updated = await runWrite(context, () => repo.rescheduleBooking(b.id, picked!.id, null), success: 'Trial moved');
    if (updated != null) {
      bumpRefresh();
      setState(() => _b = updated);
    } else {
      _load(); // e.g. CONFLICT: show the current state
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;
    return Scaffold(
      appBar: AppBar(title: const Text('Trial booking')),
      body: b == null
          ? (_loading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: EmptyState(
                    icon: Icons.error_outline,
                    title: _error?.code == 'NOT_FOUND' ? 'Booking not found' : 'Could not load the booking',
                    message: _error?.message,
                    action: FilledButton(onPressed: _load, child: const Text('Try again')),
                  ),
                ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (_error != null) SyncBanner(error: _error),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: b.state.color, borderRadius: BorderRadius.circular(20)),
                  child: DefaultTextStyle(
                    style: const TextStyle(color: HsColors.onPastel),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [StatusChip(b.state, text: b.status), const Spacer(), Text(b.bookingType)]),
                      const SizedBox(height: 12),
                      Text(b.partyName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('${fmtDayTime(b.start)} - ${fmtTime(b.end)}'),
                      Text('Trainer: ${b.trainerName ?? '-'}'),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                if (b.party != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: HsColors.card, borderRadius: BorderRadius.circular(18)),
                    child: Row(children: [
                      Expanded(
                        child: Text(b.party!.primaryPhone?.e164 ?? 'No phone number',
                            style: const TextStyle(fontSize: 15)),
                      ),
                      ContactButtons(phone: b.party!.primaryPhone, party: b.party),
                    ]),
                  ),
                if (b.notes != null) ...[const SizedBox(height: 12), Text('Notes: ${b.notes}')],
                if (b.cancellationReason != null) ...[const SizedBox(height: 8), Text('Cancelled: ${b.cancellationReason}')],
                if (b.completionNotes != null) ...[const SizedBox(height: 8), Text('Result: ${b.completionNotes}')],
                if (b.activityId != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: b.activityId!)),
                    ),
                    icon: const Icon(Icons.event_note),
                    label: const Text('Open in calendar'),
                  ),
                ],
              ]),
            ),
      bottomNavigationBar: b == null || !b.isActive
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: HsColors.completed),
                      onPressed: _complete,
                      child: const Text('Complete'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: HsColors.rescheduled),
                      onPressed: _reschedule,
                      child: const Text('Reschedule'),
                    ),
                  ),
                  IconButton(tooltip: 'Cancel booking', onPressed: _cancel, icon: const Icon(Icons.cancel_outlined)),
                ]),
              ),
            ),
    );
  }
}
