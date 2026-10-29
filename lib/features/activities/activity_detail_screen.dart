import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../core/repository.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/contact_actions.dart';
import '../customers/customer_detail_screen.dart';
import '../trials/trial_detail_screen.dart';
import 'activity_form.dart';

class ActivityDetailScreen extends StatefulWidget {
  const ActivityDetailScreen({super.key, required this.activityId});

  final String activityId;

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  Activity? _a;
  ApiException? _error;
  DateTime? _syncedAt;
  bool _loading = true;

  Repository get _repo => context.read<SessionController>().repo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = _repo;
    final cached = repo.cachedActivity(widget.activityId);
    setState(() {
      _a ??= cached;
      _syncedAt ??= repo.cached('act:${widget.activityId}')?.syncedAt;
      _loading = true;
    });
    try {
      final a = await repo.activity(widget.activityId);
      if (!mounted) return;
      setState(() {
        _a = a;
        _error = null;
        _syncedAt = DateTime.now();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _afterWrite(Activity? updated) async {
    if (updated == null) return;
    bumpRefresh();
    await _load();
  }

  // ------------------------------------------------------------ actions

  Future<void> _complete() async {
    final outcome = TextEditingController();
    final notes = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Mark as completed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(controller: outcome, decoration: const InputDecoration(labelText: 'Outcome (e.g. Demo booked)')),
          const SizedBox(height: 10),
          TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes (optional)')),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Complete')),
        ]),
      ),
    );
    if (ok != true || !mounted) return;
    final updated = await runWrite(
      context,
      () => _repo.updateStatus(_a!.id, 'Completed',
          outcome: outcome.text.trim().isEmpty ? null : outcome.text.trim(),
          notes: notes.text.trim().isEmpty ? null : notes.text.trim()),
      success: 'Completed and saved to ERP',
    );
    await _afterWrite(updated);
  }

  Future<void> _delete(Activity a) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete this ${a.activityType.toLowerCase()}?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('"${a.title}" will be removed from ERP and its reminders stop. This can\'t be undone.'),
          const SizedBox(height: 12),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HsColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.deleteActivity(a.id, reason: reason.text.trim().isEmpty ? null : reason.text.trim());
      bumpRefresh();
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Deleted from ERP')));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reschedule() async {
    final a = _a!;
    final now = DateTime.now();
    final initial = (a.start != null && a.start!.isAfter(now)) ? a.start! : now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'New date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial), helpText: 'New time');
    if (time == null || !mounted) return;
    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final duration = (a.start != null && a.end != null) ? a.end!.difference(a.start!) : const Duration(minutes: 30);
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reschedule'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('New time: ${fmtDayTime(start)}'),
          const SizedBox(height: 12),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reschedule')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final updated = await runWrite(
      context,
      () => _repo.reschedule(a.id, start, start.add(duration), reason.text.trim().isEmpty ? null : reason.text.trim()),
      success: 'Rescheduled - saved to ERP',
    );
    await _afterWrite(updated);
  }

  Future<void> _setStatus(String status, {required String confirmTitle, String? success, bool askReason = false}) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(confirmTitle),
        content: askReason
            ? TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (optional)'))
            : null,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final updated = await runWrite(
      context,
      () => _repo.updateStatus(_a!.id, status, notes: reason.text.trim().isEmpty ? null : reason.text.trim()),
      success: success,
    );
    await _afterWrite(updated);
  }

  Future<void> _addNote() async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add note'),
        content: TextField(controller: note, maxLines: 4, autofocus: true, decoration: const InputDecoration(hintText: 'What happened?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || note.text.trim().isEmpty || !mounted) return;
    final done = await runWrite(context, () async {
      await _repo.addNote(_a!.id, note.text.trim());
      return true;
    }, success: 'Note saved');
    if (done == true) await _load();
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final a = _a;
    return Scaffold(
      appBar: AppBar(
        title: Text(a?.activityType ?? 'Activity'),
        actions: [
          if (a != null && a.isOpen && a.trialBooking == null)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                if (await openActivityEdit(context, a)) _load();
              },
            ),
          if (a != null && a.trialBooking == null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(a),
            ),
        ],
      ),
      body: a == null
          ? (_loading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: EmptyState(
                    icon: Icons.error_outline,
                    title: _error?.code == 'NOT_FOUND' ? 'Activity not found' : 'Could not load this activity',
                    message: _error?.code == 'NOT_FOUND' ? 'It may have been reassigned or deleted.' : _error?.message,
                    action: FilledButton(onPressed: _load, child: const Text('Try again')),
                  ),
                ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
                SyncBanner(syncedAt: _syncedAt, error: _error),
                _header(a),
                if (a.party != null) _partyCard(a),
                _detailsCard(a),
                if (a.history.isNotEmpty) _historyCard(a),
              ]),
            ),
      bottomNavigationBar: a == null || !a.isOpen ? null : _actionBar(a),
    );
  }

  Widget _header(Activity a) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: a.state.color, borderRadius: BorderRadius.circular(20)),
      child: DefaultTextStyle(
        style: const TextStyle(color: HsColors.onPastel),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            StatusChip(a.state, text: a.status),
            const Spacer(),
            Text('${a.priority} priority', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          Text(a.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.event, size: 16, color: HsColors.onPastel),
            const SizedBox(width: 6),
            Expanded(
              child: Text(a.start == null
                  ? 'No date set'
                  : '${DateFormat('EEEE d MMMM').format(a.start!)}, ${fmtTime(a.start)} - ${fmtTime(a.end)}'),
            ),
          ]),
          if (a.isOverdue)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Overdue', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF8B1E1E))),
            ),
          if (a.rescheduleCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Rescheduled ${a.rescheduleCount} time${a.rescheduleCount == 1 ? '' : 's'}'),
            ),
        ]),
      ),
    );
  }

  Widget _partyCard(Activity a) {
    final p = a.party!;
    final repo = _repo;
    return _Box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CustomerDetailScreen(doctype: p.doctype, name: p.id, title: p.name)),
          ),
          child: Row(children: [
            CircleAvatar(
              backgroundColor: HsColors.cardHigh,
              child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase()),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text([p.kind, if (p.subtitle != null) p.subtitle!].join(' - '),
                    style: const TextStyle(color: HsColors.textSecondary, fontSize: 13)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: HsColors.textSecondary),
          ]),
        ),
        if (p.phones.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('No phone number in ERP for this contact.', style: TextStyle(color: HsColors.textSecondary)),
          ),
        for (final phone in p.phones)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(phone.e164 ?? phone.raw, style: const TextStyle(fontSize: 15)),
                  Text(phone.valid ? (phone.label ?? 'Phone') : 'Invalid number - fix in ERP',
                      style: TextStyle(fontSize: 12, color: phone.valid ? HsColors.textSecondary : HsColors.danger)),
                ]),
              ),
              ContactButtons(
                phone: phone,
                party: a.party,
                activityId: a.id,
                onCall: () => repo.logContact(a.id, 'Call').catchError((_) {}),
                onWhatsApp: () => repo.logContact(a.id, 'WhatsApp').catchError((_) {}),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _detailsCard(Activity a) {
    final rows = <(IconData, String, String)>[
      (Icons.category_outlined, 'Type', a.activityType),
      if (a.visitType != null) (Icons.tour_outlined, 'Visit type', a.visitType!),
      if (a.people.length > 1)
        (Icons.groups_2_outlined, 'People', a.people.map((p) => p.status == 'Completed' ? '${p.name} ✓' : p.name).join(', ')),
      if (a.location != null) (Icons.place_outlined, 'Location', a.location!),
      if (a.outcome != null) (Icons.flag_outlined, 'Outcome', a.outcome!),
      if (a.completionNotes != null) (Icons.notes, 'Notes', a.completionNotes!),
    ];
    return _Box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(r.$1, size: 18, color: HsColors.textSecondary),
              const SizedBox(width: 10),
              SizedBox(width: 90, child: Text(r.$2, style: const TextStyle(color: HsColors.textSecondary))),
              Expanded(child: Text(r.$3)),
            ]),
          ),
        if (a.description != null) ...[
          const Divider(height: 24),
          Text(_stripHtml(a.description!)),
        ],
        if (a.meetingLink != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse(a.meetingLink!), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.video_call_outlined),
              label: const Text('Join meeting link'),
            ),
          ),
        if (a.trialBooking != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TrialDetailScreen(bookingId: a.trialBooking!)),
              ),
              icon: const Icon(Icons.school_outlined),
              label: const Text('Open trial booking'),
            ),
          ),
      ]),
    );
  }

  Widget _historyCard(Activity a) {
    return _Box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('History', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 8),
        for (final h in a.history)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 5),
                child: Icon(Icons.circle, size: 8, color: HsColors.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_describe(h), style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (h.reason != null && h.eventType != 'Contact Attempt') Text(h.reason!),
                  Text('${h.actorName ?? ''} - ${fmtDayTime(h.at)}${h.source == 'Mobile' ? ' - app' : ''}',
                      style: const TextStyle(color: HsColors.textSecondary, fontSize: 12)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }

  String _describe(HistoryEntry h) => switch (h.eventType) {
        'Rescheduled' => 'Rescheduled from ${fmtDayTime(h.oldStart)} to ${fmtDayTime(h.newStart)}',
        'Status Changed' => 'Status: ${h.oldStatus ?? '-'} -> ${h.newStatus ?? '-'}',
        'Contact Attempt' => 'Contacted via ${h.reason ?? 'phone'}',
        'Note Added' => 'Note',
        _ => h.eventType,
      };

  String _stripHtml(String s) => s.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll('&nbsp;', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  Widget _actionBar(Activity a) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        color: HsColors.background,
        child: Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: HsColors.completed),
              onPressed: _complete,
              icon: const Icon(Icons.check),
              label: const Text('Complete'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: HsColors.rescheduled),
              onPressed: a.trialBooking != null
                  ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrialDetailScreen(bookingId: a.trialBooking!)))
                  : _reschedule,
              icon: const Icon(Icons.update),
              label: const Text('Reschedule'),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            onSelected: (v) => switch (v) {
              'note' => _addNote(),
              'progress' => _setStatus('In Progress', confirmTitle: 'Mark as in progress?', success: 'Marked in progress'),
              'cancel' => _setStatus('Cancelled', confirmTitle: 'Cancel this activity?', success: 'Activity cancelled', askReason: true),
              _ => null,
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'note', child: Text('Add note')),
              if (a.status != 'In Progress') const PopupMenuItem(value: 'progress', child: Text('Mark in progress')),
              const PopupMenuItem(value: 'cancel', child: Text('Cancel activity')),
            ],
          ),
        ]),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: HsColors.card, borderRadius: BorderRadius.circular(18)),
        child: child,
      );
}
