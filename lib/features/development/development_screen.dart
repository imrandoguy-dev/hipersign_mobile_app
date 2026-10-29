import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/development.dart';
import '../../shared/widgets/attachments.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/reminder_picker.dart';
import '../customers/party_picker.dart';

const _filters = {'open': 'Open', 'late': 'Late', 'done': 'Done', 'all': 'All'};

Color _statusColor(DevTask t) {
  if (t.late) return HsColors.overdue;
  return switch (t.status) {
    'In Progress' => HsColors.active,
    'In Review' => HsColors.rescheduled,
    'Done' => HsColors.completed,
    'Cancelled' => HsColors.cancelled,
    _ => HsColors.pending,
  };
}

/// "Deadline in 2 days" / "Due today 5:00 PM" / "3 days late"
String deadlineText(DevTask t, {DateTime? now}) {
  final d = t.deadline;
  if (d == null) return 'No deadline';
  if (!t.isOpen) return 'Deadline ${fmtDayTime(d)}';
  if (t.late) return '${t.lateText ?? 'Late'} · was due ${fmtDayTime(d)}';
  final n = now ?? DateTime.now();
  final days = DateTime(d.year, d.month, d.day).difference(DateTime(n.year, n.month, n.day)).inDays;
  if (days == 0) return 'Due today ${fmtTime(d)}';
  if (days == 1) return 'Due tomorrow ${fmtTime(d)}';
  return 'Due ${fmtDayTime(d)} (in $days days)';
}

/// Development work (kind 'dev') or team tasks (kind 'team': accounts, marketing, hiring...):
/// mine, the ones I assigned, or everyone's (managers).
class DevelopmentScreen extends StatefulWidget {
  const DevelopmentScreen({super.key, this.showBack = true, this.kind = 'dev'});
  final bool showBack;
  final String kind;

  @override
  State<DevelopmentScreen> createState() => _DevelopmentScreenState();
}

class _DevelopmentScreenState extends State<DevelopmentScreen> {
  String _scope = 'mine';
  String _filter = 'open';
  String? _team;
  List<String> _teams = [];
  List<DevTask> _items = [];
  String? _next;
  int _late = 0;
  bool _loading = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    refreshTick.addListener(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    refreshTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final p = await context.read<SessionController>().repo.devTasks(scope: _scope, filter: _filter, kind: widget.kind, team: _team);
      if (!mounted) return;
      setState(() {
        _items = p.items;
        if (p.teams.isNotEmpty) _teams = p.teams;
        _next = p.nextCursor;
        _late = p.late;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (_next == null || _loading) return;
    try {
      final p = await context.read<SessionController>().repo.devTasks(scope: _scope, filter: _filter, cursor: _next, kind: widget.kind, team: _team);
      if (mounted) setState(() {
        _items = [..._items, ...p.items];
        _next = p.nextCursor;
      });
    } on ApiException catch (_) {}
  }

  Future<void> _open(DevTask t) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DevTaskScreen(taskId: t.id, kind: widget.kind)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SessionController>().profile!;
    final team = widget.kind == 'team';
    final manager = p.can(team ? 'assign_tasks' : 'assign_development');
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.showBack,
        title: Text(team ? 'Tasks' : 'Development', style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'dev-new-${widget.kind}',
        onPressed: () async {
          final t = await Navigator.push<DevTask>(context, MaterialPageRoute(builder: (_) => DevTaskForm(kind: widget.kind, team: _team)));
          if (t != null) _load();
        },
        icon: const Icon(Icons.add),
        label: Text(manager ? 'Assign work' : 'New task'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) _more();
            return false;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: SegmentedButton<String>(
                  segments: [
                    const ButtonSegment(value: 'mine', label: Text('My work')),
                    const ButtonSegment(value: 'assigned', label: Text('I assigned')),
                    if (manager) const ButtonSegment(value: 'team', label: Text('Team')),
                  ],
                  selected: {_scope},
                  onSelectionChanged: (s) {
                    setState(() => _scope = s.first);
                    _load();
                  },
                ),
              ),
              if (_scope == 'mine' && _late > 0)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: HsColors.dangerBg, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(Icons.alarm, color: HsColors.danger),
                    const SizedBox(width: 10),
                    Expanded(child: Text('$_late task${_late > 1 ? 's are' : ' is'} past the deadline')),
                  ]),
                ),
              if (team && _teams.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    children: [
                      for (final t in <String?>[null, ..._teams])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(t ?? 'All teams'),
                            selected: _team == t,
                            onSelected: (_) {
                              setState(() => _team = t);
                              _load();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  children: [
                    for (final f in _filters.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f.value),
                          selected: _filter == f.key,
                          onSelected: (_) {
                            setState(() => _filter = f.key);
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
              if (_error != null) SyncBanner(error: _error),
              if (_loading && _items.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
              if (!_loading && _items.isEmpty && _error == null)
                EmptyState(
                  icon: team ? Icons.task_alt : Icons.code,
                  title: _filter == 'late' ? 'Nothing is late' : (team ? 'No tasks here' : 'No development tasks here'),
                  message: manager
                      ? (team
                          ? 'Use "Assign work" to give a task to anyone (accounts, marketing, hiring...) with a deadline.'
                          : 'Use "Assign work" to give a task to a developer with a deadline.')
                      : null,
                ),
              for (final t in _items) DevTaskCard(task: t, showDeveloper: _scope != 'mine', onTap: () => _open(t)),
            ],
          ),
        ),
      ),
    );
  }
}

class DevTaskCard extends StatelessWidget {
  const DevTaskCard({super.key, required this.task, required this.showDeveloper, required this.onTap});
  final DevTask task;
  final bool showDeveloper;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = task;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: _statusColor(t),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: DefaultTextStyle(
              style: const TextStyle(color: HsColors.onPastel),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  _Chip(t.late ? 'Late' : t.status),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(t.late ? Icons.alarm : Icons.event, size: 15, color: t.late ? HsColors.danger : HsColors.onPastel),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(deadlineText(t),
                        style: TextStyle(fontSize: 13, color: t.late ? HsColors.danger : null, fontWeight: t.late ? FontWeight.w700 : null)),
                  ),
                ]),
                if (showDeveloper || t.project != null || (t.team != null && t.kind == 'team') || t.attachments > 0 || t.priority == 'High' || t.priority == 'Urgent') ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (showDeveloper) t.developerName,
                      if (t.kind == 'team' && t.team != null) t.team!,
                      if (t.project != null) t.project!,
                      if (t.attachments > 0) '📎 ${t.attachments}',
                      if (t.priority == 'High' || t.priority == 'Urgent') '${t.priority} priority',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

/// One development task: status, deadline, notes; edit when you assigned it.
class DevTaskScreen extends StatefulWidget {
  const DevTaskScreen({super.key, required this.taskId, this.kind = 'dev'});
  final String taskId;
  final String kind;

  @override
  State<DevTaskScreen> createState() => _DevTaskScreenState();
}

class _DevTaskScreenState extends State<DevTaskScreen> {
  DevTask? _t;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final t = await context.read<SessionController>().repo.devTask(widget.taskId, kind: widget.kind);
      if (mounted) setState(() {
        _t = t;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _update(Map<String, dynamic> values, {String? success}) async {
    final repo = context.read<SessionController>().repo;
    final t = await runWrite(context, () => repo.devUpdate(widget.taskId, values, kind: widget.kind), success: success);
    if (t != null) {
      bumpRefresh();
      _load();
    }
  }

  Future<void> _addNote() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Progress note'),
        content: TextField(controller: c, autofocus: true, maxLines: 4, decoration: const InputDecoration(hintText: 'What was done, what is blocking...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (text != null && text.isNotEmpty) await _update({'note': text}, success: 'Note added');
  }

  Future<void> _reminders() async {
    final t = _t!;
    final r = await pickReminders(context, initial: t.reminders);
    if (r == null) return;
    await _update({'reminders': r.offsets.where((m) => m > 0).join(',')}, success: 'Reminders saved');
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kind == 'team' ? 'Task' : 'Development task'),
        actions: [
          if (t != null && t.canEdit)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final saved = await Navigator.push<DevTask>(context, MaterialPageRoute(builder: (_) => DevTaskForm(task: t, kind: widget.kind)));
                if (saved != null) _load();
              },
            ),
        ],
      ),
      body: t == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : EmptyState(icon: Icons.error_outline, title: 'Could not load the task', message: _error!.message,
                      action: FilledButton(onPressed: _load, child: const Text('Try again'))),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: _statusColor(t), borderRadius: BorderRadius.circular(20)),
                  child: DefaultTextStyle(
                    style: const TextStyle(color: HsColors.onPastel),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [_Chip(t.late ? 'Late' : t.status), const Spacer(), Text('${t.priority} priority')]),
                      const SizedBox(height: 10),
                      Text(t.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(deadlineText(t), style: TextStyle(fontWeight: FontWeight.w600, color: t.late ? HsColors.danger : null)),
                      const SizedBox(height: 4),
                      Text('${t.kind == 'team' ? 'Assigned to' : 'Developer'}: ${t.developerName}'),
                      if (t.kind == 'team' && t.team != null) Text('Team: ${t.team}'),
                      if (t.customer != null) Text('Customer: ${t.customerName ?? t.customer}'),
                      if (t.assignedByName != null) Text('Assigned by: ${t.assignedByName}'),
                      if (t.project != null) Text('Project: ${t.project}'),
                      if (t.deadlineChanges > 0) Text('Deadline moved ${t.deadlineChanges} time${t.deadlineChanges > 1 ? 's' : ''}'),
                      if (t.completedOn != null) Text('Completed ${fmtDayTime(t.completedOn)}'),
                    ]),
                  ),
                ),
                if (t.description != null) ...[
                  const SizedBox(height: 16),
                  Text(t.kind == 'team' ? 'Details' : 'What to build', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(t.description!, style: const TextStyle(height: 1.35)),
                ],
                const SizedBox(height: 16),
                AttachmentsSection(
                  key: ValueKey('att-${t.id}'),
                  doctype: t.kind == 'team' ? 'Team Task' : 'Development Task',
                  name: t.id,
                ),
                const SizedBox(height: 16),
                if (t.isOpen) ...[
                  const Text('Status', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in const ['Open', 'In Progress', 'In Review'])
                      ChoiceChip(label: Text(s), selected: t.status == s, onSelected: (_) => _update({'status': s})),
                  ]),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                    onPressed: () => _update({'status': 'Done'}, success: 'Marked as done'),
                    icon: const Icon(Icons.check),
                    label: const Text('Mark as done'),
                  ),
                ] else
                  OutlinedButton.icon(
                    onPressed: () => _update({'status': 'Open'}, success: 'Reopened'),
                    icon: const Icon(Icons.undo),
                    label: const Text('Reopen'),
                  ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Reminders before the deadline'),
                  subtitle: Text(t.reminders.isEmpty ? 'None' : describeReminders(t.reminders)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _reminders,
                ),
                const Divider(),
                Row(children: [
                  const Text('Progress notes', style: TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton.icon(onPressed: _addNote, icon: const Icon(Icons.add), label: const Text('Add note')),
                ]),
                if (t.notes.isEmpty) const Text('No notes yet.', style: TextStyle(color: HsColors.textSecondary)),
                for (final n in t.notes)
                  Card(
                    elevation: 0,
                    color: HsColors.card,
                    child: ListTile(
                      title: Text(n.text),
                      subtitle: Text([if (n.by != null) n.by!, if (n.at != null) fmtDayTime(n.at)].join(' · ')),
                    ),
                  ),
              ]),
            ),
    );
  }
}

/// Assign new work (or edit it): title, details, developer, deadline, priority, reminders.
class DevTaskForm extends StatefulWidget {
  const DevTaskForm({super.key, this.task, this.kind = 'dev', this.team});
  final DevTask? task;
  final String kind;
  final String? team; // preselected team (team tasks)

  @override
  State<DevTaskForm> createState() => _DevTaskFormState();
}

class _DevTaskFormState extends State<DevTaskForm> {
  late final _title = TextEditingController(text: widget.task?.title);
  late final _desc = TextEditingController(text: widget.task?.description);
  late final _project = TextEditingController(text: widget.task?.project);
  late DateTime _deadline = widget.task?.deadline ?? _defaultDeadline();
  late String _priority = widget.task?.priority ?? 'Medium';
  late List<int> _reminders = widget.task?.reminders ?? const [1440];
  String? _developer;
  List<Map<String, String>> _developers = [];
  late String? _team = widget.task?.team ?? widget.team;
  List<String> _teams = [];
  List<PendingFile> _files = [];
  late String? _customer = widget.task?.customer;
  late String? _customerName = widget.task?.customerName ?? widget.task?.customer;
  bool get _isTeam => widget.kind == 'team';

  static DateTime _defaultDeadline() {
    final n = DateTime.now().add(const Duration(days: 3));
    return DateTime(n.year, n.month, n.day, 18);
  }

  @override
  void initState() {
    super.initState();
    _developer = widget.task?.developer;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final (list, teams) = await context.read<SessionController>().repo.developers(kind: widget.kind);
        if (!mounted) return;
        setState(() {
          _developers = list;
          _teams = teams;
          _developer ??= list.length == 1 ? list.first['id'] : null;
        });
      } on ApiException catch (e) {
        showSnack(e.message, error: true);
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _project.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_deadline));
    if (t == null) return;
    setState(() => _deadline = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      return showMissing(context, 'Title missing', _isTeam ? 'Write what has to be done.' : 'Write what to build.');
    }
    if (_developer == null) {
      return showMissing(context, _isTeam ? 'Person not selected' : 'Developer not selected',
          _isTeam ? 'Choose who will do this task.' : 'Choose the developer for this work.');
    }
    final values = {
      'title': _title.text.trim(),
      'description': _desc.text.trim(),
      if (!_isTeam) 'project': _project.text.trim(),
      if (_isTeam) 'team': _team ?? '',
      'customer': _customer ?? '',
      'developer': _developer,
      'deadline': _deadline.toUtc().toIso8601String(),
      'priority': _priority,
      'reminders': _reminders.where((m) => m > 0).join(','),
    };
    final repo = context.read<SessionController>().repo;
    final task = widget.task;
    final saved = await runWrite(
      context,
      () => task == null ? repo.devCreate(values, kind: widget.kind) : repo.devUpdate(task.id, values, kind: widget.kind),
      success: task == null ? 'Task assigned' : 'Saved',
    );
    if (saved != null && _files.isNotEmpty) {
      await uploadPending(repo, _isTeam ? 'Team Task' : 'Development Task', saved.id, _files);
    }
    if (saved != null && mounted) {
      bumpRefresh();
      Navigator.pop(context, saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.task == null ? (_isTeam ? 'Assign a task' : 'Assign development work') : 'Edit task')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: _isTeam ? 'What has to be done' : 'What to build'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _desc,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Details (optional)', alignLabelWithHint: true),
        ),
        if (widget.task == null) ...[
          const SizedBox(height: 12),
          PendingAttachments(files: _files, onChanged: (f) => setState(() => _files = f)),
        ],
        const SizedBox(height: 12),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          tileColor: HsColors.card,
          leading: const Icon(Icons.storefront_outlined),
          title: Text(_customerName ?? 'Customer (optional)'),
          subtitle: _customer == null ? const Text('Pick from ERPNext customers') : null,
          trailing: _customer == null
              ? const Icon(Icons.chevron_right)
              : IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _customer = null;
                    _customerName = null;
                  }),
                ),
          onTap: () async {
            final p = await pickParty(context, kind: 'customer');
            if (p != null && mounted) {
              if (p.doctype != 'Customer') {
                showSnack('Pick a customer (not a lead).', error: true);
                return;
              }
              setState(() {
                _customer = p.id;
                _customerName = p.name;
              });
            }
          },
        ),
        if (!_isTeam) ...[
          const SizedBox(height: 12),
          TextField(controller: _project, decoration: const InputDecoration(labelText: 'Project / module (optional)')),
        ],
        if (_isTeam) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: ValueKey('teams-${_teams.length}'),
            initialValue: _teams.contains(_team) ? _team : null,
            decoration: const InputDecoration(labelText: 'Team'),
            items: [for (final t in _teams) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => setState(() => _team = v),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('devs-${_developers.length}'),
          initialValue: _developers.any((d) => d['id'] == _developer) ? _developer : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: _isTeam ? 'Assign to' : 'Developer'),
          items: [for (final d in _developers) DropdownMenuItem(value: d['id'], child: Text(d['name']!))],
          onChanged: (v) => setState(() => _developer = v),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: const Text('Deadline'),
          subtitle: Text(DateFormat('EEE d MMM yyyy, h:mm a').format(_deadline)),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: _pickDeadline,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.notifications_active_outlined),
          title: Text(_isTeam ? 'Remind them' : 'Remind the developer'),
          subtitle: Text(_reminders.where((m) => m > 0).isEmpty ? 'Only when the deadline is crossed' : describeReminders(_reminders.where((m) => m > 0).toList())),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final r = await pickReminders(context, initial: _reminders);
            if (r != null) setState(() => _reminders = r.offsets);
          },
        ),
        const SizedBox(height: 8),
        const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final p in const ['Low', 'Medium', 'High', 'Urgent'])
            ChoiceChip(label: Text(p), selected: _priority == p, onSelected: (_) => setState(() => _priority = p)),
        ]),
        const SizedBox(height: 12),
        Text(
          '${_isTeam ? 'They are' : 'The developer is'} told now, reminded before the deadline, and if it isn\'t done by the deadline you both get a "deadline crossed" alert - then every morning until it\'s done.',
          style: const TextStyle(color: HsColors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: Text(widget.task == null ? 'Assign' : 'Save')),
      ]),
    );
  }
}
