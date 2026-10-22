import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/team.dart';
import '../../shared/widgets/attachments.dart';
import '../../shared/widgets/common.dart';

Color _statusColor(String s) => switch (s) {
      'In Review' => HsColors.active,
      'Resolved' => HsColors.completed,
      'Closed' => HsColors.cancelled,
      _ => HsColors.pending,
    };

/// Problems at work, raised privately - to the CEO only, or to HR & managers.
class ConcernsScreen extends StatefulWidget {
  const ConcernsScreen({super.key, this.inbox = false});
  final bool inbox; // CEO / HR / managers: the ones raised to them

  @override
  State<ConcernsScreen> createState() => _ConcernsScreenState();
}

class _ConcernsScreenState extends State<ConcernsScreen> {
  late bool _inbox = widget.inbox;
  bool _canReview = false;
  List<Concern>? _items;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final o = await context.read<SessionController>().repo.concernOptions();
        if (mounted) setState(() => _canReview = o['can_review'] == true);
      } catch (_) {}
      _load();
    });
  }

  Future<void> _load() async {
    try {
      final r = await context.read<SessionController>().repo.concerns(scope: _inbox ? 'inbox' : 'mine');
      if (mounted) setState(() {
        _items = r.items;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(_inbox ? 'Concerns raised to me' : 'Raise a concern')),
      floatingActionButton: _inbox
          ? null
          : FloatingActionButton.extended(
              heroTag: 'con-new',
              onPressed: () async {
                final c = await Navigator.push<Concern>(context, MaterialPageRoute(builder: (_) => const ConcernForm()));
                if (c != null) _load();
              },
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Raise a concern'),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
          if (_canReview)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Mine')),
                  ButtonSegment(value: true, label: Text('Raised to me')),
                ],
                selected: {_inbox},
                onSelectionChanged: (s) {
                  setState(() {
                    _inbox = s.first;
                    _items = null;
                  });
                  _load();
                },
              ),
            ),
          if (!_inbox)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: HsColors.card, borderRadius: BorderRadius.circular(12)),
              child: const Row(children: [
                Icon(Icons.lock_outline, color: HsColors.navy),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Facing a problem with a manager, a colleague, workload or anything else? Tell us here. Only the people you choose can read it - the CEO only, or HR & managers. Your colleagues can\'t see it.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ]),
            ),
          if (_error != null) SyncBanner(error: _error),
          if (items == null && _error == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          if (items != null && items.isEmpty)
            EmptyState(icon: Icons.verified_user_outlined, title: _inbox ? 'Nothing raised to you' : 'You haven\'t raised anything'),
          for (final c in items ?? const <Concern>[])
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Material(
                color: _statusColor(c.status),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => ConcernScreen(id: c.id)));
                    _load();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: DefaultTextStyle(
                      style: const TextStyle(color: HsColors.onPastel),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(c.subject, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                          Text(c.status, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ]),
                        const SizedBox(height: 4),
                        Text([c.category, c.audience, if (_inbox && c.by != null) 'from ${c.by}', fmtDayTime(c.at)].join(' · '),
                            style: const TextStyle(fontSize: 12.5)),
                        if (c.response != null) ...[
                          const SizedBox(height: 4),
                          Text('Response: ${c.response}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                        ],
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class ConcernForm extends StatefulWidget {
  const ConcernForm({super.key});

  @override
  State<ConcernForm> createState() => _ConcernFormState();
}

class _ConcernFormState extends State<ConcernForm> {
  String _audience = 'HR & Managers';
  String _category = 'Other';
  List<String> _categories = const ['Manager', 'Colleague', 'Workload', 'Salary / Payments', 'Work Environment', 'Tools / Equipment', 'Customer', 'Other'];
  final _subject = TextEditingController();
  final _details = TextEditingController();
  List<PendingFile> _files = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final o = await context.read<SessionController>().repo.concernOptions();
        if (mounted && o['categories'] is List) setState(() => _categories = (o['categories'] as List).map((e) => e.toString()).toList());
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _subject.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_subject.text.trim().isEmpty) {
      return showMissing(context, 'Subject missing', 'Write in a few words what the problem is.');
    }
    if (_details.text.trim().isEmpty && _files.isEmpty) {
      return showMissing(context, 'Tell us what happened', 'Write the details, or record a voice note.');
    }
    final repo = context.read<SessionController>().repo;
    final c = await runWrite(
      context,
      () => repo.createConcern({'audience': _audience, 'category': _category, 'subject': _subject.text.trim(), 'details': _details.text.trim()}),
      success: _audience == 'CEO Only' ? 'Sent to the CEO' : 'Sent to HR & managers',
    );
    if (c == null) return;
    if (_files.isNotEmpty) await uploadPending(repo, 'Hipersign Concern', c.id, _files);
    if (mounted) Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Raise a concern')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Who can read it?', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        RadioGroup<String>(
          groupValue: _audience,
          onChanged: (v) => setState(() => _audience = v ?? _audience),
          child: const Column(children: [
            RadioListTile<String>(
              value: 'CEO Only',
              title: Text('CEO only'),
              subtitle: Text('Only the CEO can read it.'),
            ),
            RadioListTile<String>(
              value: 'HR & Managers',
              title: Text('HR & managers'),
              subtitle: Text('HR, the managers and the CEO can read it.'),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _categories.contains(_category) ? _category : null,
          decoration: const InputDecoration(labelText: 'It is about'),
          items: [for (final c in _categories) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => _category = v ?? 'Other'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _subject, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Subject')),
        const SizedBox(height: 12),
        TextField(
          controller: _details,
          minLines: 5,
          maxLines: 12,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'What happened?', alignLabelWithHint: true),
        ),
        const SizedBox(height: 12),
        PendingAttachments(files: _files, onChanged: (f) => setState(() => _files = f), title: 'Voice note or files (optional)'),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: _save, icon: const Icon(Icons.lock_outline), label: const Text('Send privately')),
      ]),
    );
  }
}

class ConcernScreen extends StatefulWidget {
  const ConcernScreen({super.key, required this.id});
  final String id;

  @override
  State<ConcernScreen> createState() => _ConcernScreenState();
}

class _ConcernScreenState extends State<ConcernScreen> {
  Concern? _c;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final c = await context.read<SessionController>().repo.concern(widget.id);
      if (mounted) setState(() => _c = c);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<String?> _ask(String title, String label, {String? initial}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, minLines: 3, maxLines: 8, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Send')),
        ],
      ),
    );
  }

  Future<void> _respond({String? status}) async {
    final c = _c!;
    String? text;
    if (status == null) {
      text = await _ask('Respond', 'Your response (they will see it)', initial: c.response);
      if (text == null || text.isEmpty) return;
    }
    if (!mounted) return;
    final repo = context.read<SessionController>().repo;
    final u = await runWrite(context, () => repo.respondConcern(c.id, response: text, status: status), success: 'Saved');
    if (u != null && mounted) setState(() => _c = u);
  }

  Future<void> _addMore() async {
    final text = await _ask('Add more', 'What else should they know?');
    if (text == null || text.isEmpty || !mounted) return;
    final repo = context.read<SessionController>().repo;
    final u = await runWrite(context, () => repo.addToConcern(_c!.id, text), success: 'Added');
    if (u != null && mounted) setState(() => _c = u);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(title: const Text('Concern')),
      body: c == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!.message))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: _statusColor(c.status), borderRadius: BorderRadius.circular(18)),
                child: DefaultTextStyle(
                  style: const TextStyle(color: HsColors.onPastel),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Text(c.status, style: const TextStyle(fontWeight: FontWeight.w700)), const Spacer(), const Icon(Icons.lock_outline, size: 16), Text(' ${c.audience}')]),
                    const SizedBox(height: 8),
                    Text(c.subject, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('${c.category} · ${c.isMine ? 'raised by you' : 'from ${c.by}'} · ${fmtDayTime(c.at)}'),
                  ]),
                ),
              ),
              if (c.details != null) ...[const SizedBox(height: 14), Text(c.details!, style: const TextStyle(height: 1.4))],
              if (c.response != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: HsColors.card, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Response${c.respondedBy != null ? ' from ${c.respondedBy}' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(c.response!),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              AttachmentsSection(doctype: 'Hipersign Concern', name: c.id, initial: c.files, canAdd: c.isMine || c.canRespond),
              const SizedBox(height: 20),
              if (c.isMine) OutlinedButton.icon(onPressed: _addMore, icon: const Icon(Icons.add), label: const Text('Add more to it')),
              if (c.canRespond) ...[
                FilledButton.icon(onPressed: () => _respond(), icon: const Icon(Icons.reply), label: const Text('Respond')),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final s in const ['In Review', 'Resolved', 'Closed'])
                    if (s != c.status) OutlinedButton(onPressed: () => _respond(status: s), child: Text('Mark $s')),
                ]),
              ],
            ]),
    );
  }
}
