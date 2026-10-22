import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/attachments.dart';
import '../../shared/widgets/common.dart';
import '../customers/party_picker.dart';
import 'slot_picker.dart';
import 'trial_detail_screen.dart';
import 'trial_widgets.dart';

/// Salesperson books a customer trial/training into a trainer's free time.
class BookTrialScreen extends StatefulWidget {
  const BookTrialScreen({super.key, this.party});
  final Party? party;

  @override
  State<BookTrialScreen> createState() => _BookTrialScreenState();
}

class _BookTrialScreenState extends State<BookTrialScreen> {
  late Party? _party = widget.party;
  String _type = 'ERP Trial';
  int _days = 1; // trial length in calendar days
  TrainerSlot? _slot;
  final _notes = TextEditingController();
  List<PendingFile> _files = [];
  bool _saving = false;
  int _refresh = 0;

  /// One key per intended booking: a retry after a timeout returns the same booking.
  String _key = randomKey(16);

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickParty() async {
    final p = await pickParty(context);
    if (p != null) {
      if (p.doctype == 'CRM Deal') {
        showSnack('Pick the customer or lead for a trial.', error: true);
        return;
      }
      setState(() => _party = p);
    }
  }

  Future<void> _book() async {
    if (_party == null) {
      return showMissing(context, 'Customer not selected', 'Choose the customer or lead for this trial before booking.',
          fixLabel: 'Choose customer', onFix: _pickParty);
    }
    if (_slot == null) {
      return showMissing(context, 'Time not selected',
          'Choose the trainer and the time (start and end) for the session, then tap "Use this time".');
    }
    setState(() => _saving = true);
    try {
      final repo = context.read<SessionController>().repo;
      final (b, skipped) = await repo.book(
            slotId: _slot!.id,
            customer: _party!.doctype == 'Customer' ? _party!.id : null,
            lead: _party!.doctype == 'CRM Lead' ? _party!.id : null,
            bookingType: _type,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            idempotencyKey: _key,
            trialDays: _days,
          );
      if (_files.isNotEmpty) await uploadPending(repo, 'Trial Booking', b.id, _files);
      bumpRefresh();
      if (!mounted) return;
      showSnack(_days > 1
          ? '$_days-day trial booked - first session with ${b.trainerName ?? 'trainer'}'
          : 'Trial booked with ${b.trainerName ?? 'trainer'}');
      if (skipped.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Some days were not booked'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final d in skipped)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• ${fmtDay(DateTime.parse(d['date'].toString()))}: ${d['reason']}'),
                ),
              const SizedBox(height: 6),
              const Text('Open the trial and use "Add session" to book another time for these days.'),
            ]),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        if (!mounted) return;
      }
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TrialDetailScreen(bookingId: b.id)));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isConflict) {
        // Someone else just took it: refresh availability and let the user pick again.
        setState(() {
          _slot = null;
          _refresh++;
          _key = randomKey(16);
        });
      }
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book a trial')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          tileColor: HsColors.card,
          leading: const Icon(Icons.person_search_outlined),
          title: Text(_party?.name ?? 'Choose customer or lead'),
          subtitle: _party == null ? null : Text(_party!.kind),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickParty,
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'ERP Trial', label: Text('ERP trial')),
            ButtonSegment(value: 'Training', label: Text('Training')),
            ButtonSegment(value: 'Other', label: Text('Other')),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() {
            _type = s.first;
            _slot = null;
          }),
        ),
        const SizedBox(height: 16),
        const Text('Trial length', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('How long the trial runs (working days - Sundays and holidays are skipped). Only the first session is booked now; add more sessions later from the trial, each at its own time.',
            style: TextStyle(fontSize: 12.5, color: HsColors.textSecondary)),
        const SizedBox(height: 8),
        TrialDaysPicker(days: _days, onChanged: (d) => setState(() => _days = d)),
        const SizedBox(height: 16),
        const Text('Trainer availability', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SlotPicker(
          bookingType: _type,
          selectedId: _slot?.id,
          refreshKey: _refresh,
          onPick: (s) => setState(() => _slot = s),
        ),
        const SizedBox(height: 16),
        TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes for the trainer (optional)')),
        const SizedBox(height: 12),
        PendingAttachments(
          files: _files,
          onChanged: (f) => setState(() => _files = f),
          title: 'Files & voice notes for the trainer',
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _book,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(_party == null || _slot == null
                    ? 'Book trial'
                    : (_days > 1
                        ? 'Book $_days-day trial · first session ${fmtDayTime(_slot!.start)}'
                        : 'Book ${fmtDayTime(_slot!.start)}')),
          ),
        ),
      ),
    );
  }
}
