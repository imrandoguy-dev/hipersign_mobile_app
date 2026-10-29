import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/refresh.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../core/notifications/reminder_planner.dart';
import '../../core/repository.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/reminder_picker.dart';
import '../customers/party_picker.dart';
import 'activity_detail_screen.dart';

Future<void> openActivityForm(BuildContext context, {required String type, Party? party}) {
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ActivityFormScreen(type: type, party: party), fullscreenDialog: true),
  );
}

/// Edit an open follow-up / meeting. Returns true when it was saved.
Future<bool> openActivityEdit(BuildContext context, Activity activity) async {
  final saved = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => ActivityFormScreen(type: activity.activityType, party: activity.party, existing: activity),
      fullscreenDialog: true,
    ),
  );
  return saved == true;
}

class ActivityFormScreen extends StatefulWidget {
  const ActivityFormScreen({super.key, required this.type, this.party, this.existing});

  final String type;
  final Party? party;
  final Activity? existing; // edit mode

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

  Activity? get _existing => widget.existing;
  bool get _editing => _existing != null;

  /// Who is in the meeting. Each person gets it on their own calendar.
  List<MeetingPerson> _people = [];

  @override
  void initState() {
    super.initState();
    final me = context.read<SessionController>().profile;
    if (me != null) _people = [MeetingPerson(me.user, me.fullName)];
    final a = _existing;
    if (a != null && a.people.isNotEmpty) _people = List.of(a.people);
    if (a != null) {
      _title.text = a.title;
      _notes.text = a.description ?? '';
      _location.text = a.location ?? '';
      if (a.start != null) _start = a.start!;
      if (a.start != null && a.end != null) {
        final m = a.end!.difference(a.start!).inMinutes;
        _minutes = const [15, 30, 45, 60, 90, 120].contains(m) ? m : 30;
        if (!const [15, 30, 45, 60, 90, 120].contains(m)) _customMinutes = m;
      }
      _priority = const ['Low', 'Medium', 'High'].contains(a.priority) ? a.priority : 'Medium';
      _reminders = a.reminderOffsets;
    }
  }

  int? _customMinutes; // an existing duration that isn't in the list
  List<int>? _reminders; // this activity's own reminders; null = my reminder setting

  List<int> get _myReminders {
    final cache = context.read<SessionController>().cache;
    final own = parseOffsets(cache.getPref(reminderOffsetsPref));
    if (own.isNotEmpty) return own;
    final m = int.tryParse(cache.getPref(reminderMinutesPref) ?? '') ?? 15;
    return {m, 0}.toList();
  }

  Widget _remindersTile() {
    final mine = _myReminders;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: Theme.of(context).colorScheme.surface,
      leading: const Icon(Icons.alarm_outlined),
      title: const Text('Reminders'),
      subtitle: Text(_reminders == null ? 'My setting: ${describeReminders(mine)}' : describeReminders(_reminders!)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final r = await pickReminders(
          context,
          initial: _reminders ?? mine,
          allowDefault: true,
          initiallyDefault: _reminders == null,
          defaultText: describeReminders(mine),
        );
        if (r != null) setState(() => _reminders = r.useDefault ? null : r.offsets);
      },
    );
  }
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
      firstDate: _start.isBefore(DateTime(now.year, now.month, now.day))
          ? DateTime(_start.year, _start.month, _start.day)
          : DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t != null) setState(() => _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute));
  }

  Future<void> _saveEdit() async {
    final a = _existing!;
    if (_party == null) return _missingParty();
    final title = _title.text.trim().isEmpty ? '$_type - ${_party!.name}' : _title.text.trim();
    final minutes = _customMinutes ?? _minutes;
    final values = <String, dynamic>{
      if (title != a.title) 'title': title,
      if (_type != a.activityType && a.activityType != 'Trial') 'activity_type': _type,
      if (_priority != a.priority) 'priority': _priority,
      if (_notes.text.trim() != (a.description ?? '')) 'description': _notes.text.trim(),
      if (_location.text.trim() != (a.location ?? '')) 'location': _location.text.trim(),
      if ((_reminders ?? const []).join(',') != (a.reminderOffsets ?? const []).join(','))
        'reminder_offsets': _reminders == null ? '' : _reminders!.join(','),
      if (_party!.id != a.party?.id || _party!.doctype != a.party?.doctype) ...{
        'reference_doctype': _party!.doctype,
        'reference_name': _party!.id,
      },
      if (_type == 'Meeting' && !_samePeople(a.people)) 'people': jsonEncode(_people.map((p) => p.id).toList()),
      if (a.start == null || _start != a.start || (a.end != null && a.end!.difference(a.start!).inMinutes != minutes)) ...{
        'start': Repository.iso(_start),
        'end': Repository.iso(_start.add(Duration(minutes: minutes))),
      },
    };
    if (values.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await context.read<SessionController>().repo.updateActivity(a.id, values);
      bumpRefresh();
      if (!mounted) return;
      if (saved == null) {
        showSnack('You are no longer in this meeting');
        Navigator.of(context)
          ..pop(true)
          ..maybePop();
        return;
      }
      showSnack('Saved to ERP');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_editing) return _saveEdit();
    if (_party == null) return _missingParty();
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
        if (_reminders != null) 'reminder_offsets': _reminders!.join(','),
        if (_type == 'Meeting' && _people.isNotEmpty) 'people': jsonEncode(_people.map((p) => p.id).toList()),
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

  bool _samePeople(List<MeetingPerson> before) {
    if (before.isEmpty) return _people.length <= 1;
    return before.map((p) => p.id).toSet().containsAll(_people.map((p) => p.id)) && before.length == _people.length;
  }

  Future<void> _pickPeople() async {
    final repo = context.read<SessionController>().repo;
    List<MeetingPerson> all;
    try {
      all = await repo.meetingPeople();
    } on ApiException catch (e) {
      _snack(e.message);
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<List<MeetingPerson>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PeopleSheet(all: all, selected: _people.map((p) => p.id).toSet()),
    );
    if (picked != null && picked.isNotEmpty) setState(() => _people = picked);
  }

  Widget _peopleTile() {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: Theme.of(context).colorScheme.surface,
      leading: const Icon(Icons.group_add_outlined),
      title: Text(_people.length <= 1 ? 'People' : 'People (${_people.length})'),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in _people)
            Chip(
              label: Text(p.name, overflow: TextOverflow.ellipsis),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onDeleted: _people.length > 1 ? () => setState(() => _people = _people.where((x) => x.id != p.id).toList()) : null,
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onPressed: _pickPeople,
          ),
        ]),
      ),
      onTap: _pickPeople,
    );
  }

  Future<void> _pickParty() async {
    final p = await pickParty(context);
    if (p != null) setState(() => _party = p);
  }

  Future<void> _missingParty() => showMissing(
        context,
        'Customer not selected',
        'Choose the customer or lead for this ${_type.toLowerCase()} before saving.',
        fixLabel: 'Choose customer',
        onFix: _pickParty,
      );

  void _snack(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit ${_type.toLowerCase()}' : 'New ${_type.toLowerCase()}'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_type != 'Trial') SegmentedButton<String>(
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
          onTap: _pickParty,
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
          initialValue: _customMinutes ?? _minutes,
          decoration: const InputDecoration(labelText: 'Duration'),
          items: [if (_customMinutes != null) _customMinutes!, 15, 30, 45, 60, 90, 120]
              .map((m) => DropdownMenuItem(value: m, child: Text(m < 60 ? '$m min' : '${m / 60} h'.replaceAll('.0', ''))))
              .toList(),
          onChanged: (v) => setState(() {
            _minutes = v ?? 30;
            _customMinutes = null;
          }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _priority,
          decoration: const InputDecoration(labelText: 'Priority'),
          items: const ['Low', 'Medium', 'High'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
          onChanged: (v) => setState(() => _priority = v ?? 'Medium'),
        ),
        if (_priority == 'High')
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 4),
            child: Text('High priority reminders ring like an alarm (can be turned off in Settings).',
                style: TextStyle(fontSize: 12.5)),
          ),
        const SizedBox(height: 12),
        _remindersTile(),
        if (_type == 'Meeting') ...[
          const SizedBox(height: 12),
          _peopleTile(),
          const SizedBox(height: 12),
          TextField(controller: _location, decoration: const InputDecoration(labelText: 'Location (optional)')),
        ],
        const SizedBox(height: 12),
        TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes (optional)')),
      ]),
    );
  }
}


/// Choose several people from the team, with search.
class _PeopleSheet extends StatefulWidget {
  const _PeopleSheet({required this.all, required this.selected});

  final List<MeetingPerson> all;
  final Set<String> selected;

  @override
  State<_PeopleSheet> createState() => _PeopleSheetState();
}

class _PeopleSheetState extends State<_PeopleSheet> {
  late final Set<String> _sel = {...widget.selected};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = widget.all.where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || p.id.toLowerCase().contains(q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            child: Row(children: [
              Expanded(child: Text('People in this meeting', style: Theme.of(context).textTheme.titleMedium)),
              FilledButton(
                onPressed: _sel.isEmpty
                    ? null
                    : () => Navigator.pop(context, widget.all.where((p) => _sel.contains(p.id)).toList()),
                child: Text('Done (${_sel.length})'),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name'),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final p = list[i];
                return CheckboxListTile(
                  value: _sel.contains(p.id),
                  title: Text(p.name),
                  subtitle: p.name == p.id ? null : Text(p.id, style: const TextStyle(fontSize: 12)),
                  onChanged: (v) => setState(() => v == true ? _sel.add(p.id) : _sel.remove(p.id)),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
