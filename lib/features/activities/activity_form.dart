import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/refresh.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../core/repository.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../customers/party_picker.dart';
import 'activity_detail_screen.dart';

Future<void> openActivityForm(BuildContext context, {required String type, Party? party}) {
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ActivityFormScreen(type: type, party: party), fullscreenDialog: true),
  );
}

class ActivityFormScreen extends StatefulWidget {
  const ActivityFormScreen({super.key, required this.type, this.party});

  final String type;
  final Party? party;

  @override
  State<ActivityFormScreen> createState() => _ActivityFormScreenState();
}

class _ActivityFormScreenState extends State<ActivityFormScreen> {
  late String _type = widget.type;
  late Party? _party = widget.party;
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _location = TextEditingController();
  DateTime _start = _nextSlot();
  int _minutes = 30;
  String _priority = 'Medium';
  bool _saving = false;

  /// Generated once per form, so "Try again" after a timeout can never create a duplicate.
  final String _idempotencyKey = randomKey(16);

  static DateTime _nextSlot() {
    final n = DateTime.now().add(const Duration(hours: 1));
    return DateTime(n.year, n.month, n.day, n.hour, n.minute < 30 ? 30 : 0).add(Duration(hours: n.minute < 30 ? 0 : 1));
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t != null) setState(() => _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    if (_party == null) {
      _snack('Choose a customer or lead.');
      return;
    }
    final title = _title.text.trim().isEmpty ? '$_type - ${_party!.name}' : _title.text.trim();
    setState(() => _saving = true);
    final repo = context.read<SessionController>().repo;
    try {
      final created = await repo.createActivity({
        'title': title,
        'activity_type': _type,
        'reference_doctype': _party!.doctype,
        'reference_name': _party!.id,
        'start': Repository.iso(_start),
        'end': Repository.iso(_start.add(Duration(minutes: _minutes))),
        'priority': _priority,
        'description': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'location': _location.text.trim().isEmpty ? null : _location.text.trim(),
        'idempotency_key': _idempotencyKey,
      });
      bumpRefresh();
      if (!mounted) return;
      showSnack('$_type saved to ERP');
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: created.id)));
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('New ${_type.toLowerCase()}'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Follow-up', label: Text('Follow-up'), icon: Icon(Icons.phone_callback_outlined)),
            ButtonSegment(value: 'Meeting', label: Text('Meeting'), icon: Icon(Icons.groups_2_outlined)),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
        const SizedBox(height: 16),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          tileColor: Theme.of(context).colorScheme.surface,
          leading: const Icon(Icons.person_search_outlined),
          title: Text(_party?.name ?? 'Choose customer or lead'),
          subtitle: _party == null ? null : Text(_party!.kind),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final p = await pickParty(context);
            if (p != null) setState(() => _party = p);
          },
        ),
        const SizedBox(height: 12),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title (optional)')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.event), label: Text(fmtDay(_start))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(onPressed: _pickTime, icon: const Icon(Icons.schedule), label: Text(fmtTime(_start))),
          ),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _minutes,
          decoration: const InputDecoration(labelText: 'Duration'),
          items: const [15, 30, 45, 60, 90, 120]
              .map((m) => DropdownMenuItem(value: m, child: Text(m < 60 ? '$m min' : '${m / 60} h'.replaceAll('.0', ''))))
              .toList(),
          onChanged: (v) => setState(() => _minutes = v ?? 30),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _priority,
          decoration: const InputDecoration(labelText: 'Priority'),
          items: const ['Low', 'Medium', 'High'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
          onChanged: (v) => setState(() => _priority = v ?? 'Medium'),
        ),
        if (_type == 'Meeting') ...[
          const SizedBox(height: 12),
          TextField(controller: _location, decoration: const InputDecoration(labelText: 'Location (optional)')),
        ],
        const SizedBox(height: 12),
        TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes (optional)')),
      ]),
    );
  }
}
