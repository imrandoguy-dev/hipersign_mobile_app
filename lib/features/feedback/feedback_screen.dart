import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/team.dart';
import '../../shared/widgets/attachments.dart';
import '../../shared/widgets/common.dart';

const _kindIcon = {'Bug': Icons.bug_report_outlined, 'Improvement': Icons.auto_fix_high_outlined, 'Idea': Icons.lightbulb_outline};

Color _statusColor(String s) => switch (s) {
      'Planned' => HsColors.rescheduled,
      'In Progress' => HsColors.active,
      'Done' => HsColors.completed,
      'Not Planned' => HsColors.cancelled,
      _ => HsColors.pending,
    };

/// App bugs and improvement ideas: anyone posts and votes, the team replies.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  String _filter = 'open';
  String _sort = 'top';
  List<Suggestion>? _items;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final r = await context.read<SessionController>().repo.suggestions(filter: _filter, sort: _sort);
      if (mounted) setState(() {
        _items = r.items;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _vote(Suggestion s) async {
    try {
      final updated = await context.read<SessionController>().repo.voteSuggestion(s.id);
      if (mounted) setState(() => _items = [for (final x in _items!) x.id == s.id ? updated : x]);
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('App suggestions')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fb-new',
        onPressed: () async {
          final created = await Navigator.push<Suggestion>(context, MaterialPageRoute(builder: (_) => const SuggestionForm()));
          if (created != null) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Suggest / report a bug'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Something not working, or an idea to make the app better? Post it here. Tap 👍 on the ones you also want.',
                style: TextStyle(color: HsColors.textSecondary)),
          ),
          SizedBox(
            height: 48,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), children: [
              for (final f in const {'open': 'Open', 'done': 'Finished', 'mine': 'Mine', 'all': 'All'}.entries)
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
              const SizedBox(width: 8),
              ActionChip(
                avatar: Icon(_sort == 'top' ? Icons.thumb_up_alt_outlined : Icons.schedule, size: 18),
                label: Text(_sort == 'top' ? 'Most votes' : 'Newest'),
                onPressed: () {
                  setState(() => _sort = _sort == 'top' ? 'new' : 'top');
                  _load();
                },
              ),
            ]),
          ),
          if (_error != null) SyncBanner(error: _error),
          if (items == null && _error == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          if (items != null && items.isEmpty)
            const EmptyState(icon: Icons.lightbulb_outline, title: 'Nothing here yet', message: 'Be the first to suggest something.'),
          for (final s in items ?? const <Suggestion>[])
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Material(
                color: HsColors.card,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => SuggestionScreen(id: s.id)));
                    _load();
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(_kindIcon[s.kind] ?? Icons.lightbulb_outline, color: s.kind == 'Bug' ? HsColors.danger : HsColors.navy),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            _Pill(s.status, _statusColor(s.status)),
                            Text('${s.kind} · ${s.by ?? ''}', style: const TextStyle(fontSize: 12.5, color: HsColors.textSecondary)),
                          ]),
                          if (s.reply != null) ...[
                            const SizedBox(height: 4),
                            Text('Team: ${s.reply}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                          ],
                        ]),
                      ),
                      Column(children: [
                        IconButton(
                          tooltip: s.voted ? 'Remove my vote' : 'I want this too',
                          onPressed: () => _vote(s),
                          icon: Icon(s.voted ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined, color: HsColors.navy),
                        ),
                        Text('${s.votes}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: HsColors.onPastel)),
      );
}

class SuggestionForm extends StatefulWidget {
  const SuggestionForm({super.key});

  @override
  State<SuggestionForm> createState() => _SuggestionFormState();
}

class _SuggestionFormState extends State<SuggestionForm> {
  String _kind = 'Improvement';
  final _title = TextEditingController();
  final _details = TextEditingController();
  List<PendingFile> _files = [];

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      return showMissing(context, 'Title missing', 'Write in a few words what is wrong or what you want.');
    }
    final repo = context.read<SessionController>().repo;
    String? version;
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    if (!mounted) return;
    final s = await runWrite(
      context,
      () => repo.createSuggestion({'kind': _kind, 'title': _title.text.trim(), 'details': _details.text.trim(), 'app_version': version}),
      success: 'Thanks! Posted for the team',
    );
    if (s == null) return;
    if (_files.isNotEmpty) await uploadPending(repo, 'Hipersign Feedback', s.id, _files);
    if (mounted) Navigator.pop(context, s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New suggestion')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Bug', label: Text('Bug'), icon: Icon(Icons.bug_report_outlined)),
            ButtonSegment(value: 'Improvement', label: Text('Improve'), icon: Icon(Icons.auto_fix_high_outlined)),
            ButtonSegment(value: 'Idea', label: Text('Idea'), icon: Icon(Icons.lightbulb_outline)),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: _kind == 'Bug' ? 'What is not working?' : 'What should be better?'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _details,
          minLines: 4,
          maxLines: 10,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: _kind == 'Bug' ? 'Steps: what you did, what happened, what you expected' : 'Details (optional)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        PendingAttachments(files: _files, onChanged: (f) => setState(() => _files = f), title: 'Screenshots, files or a voice note'),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: const Text('Post')),
      ]),
    );
  }
}

class SuggestionScreen extends StatefulWidget {
  const SuggestionScreen({super.key, required this.id});
  final String id;

  @override
  State<SuggestionScreen> createState() => _SuggestionScreenState();
}

class _SuggestionScreenState extends State<SuggestionScreen> {
  Suggestion? _s;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final s = await context.read<SessionController>().repo.suggestion(widget.id);
      if (mounted) setState(() => _s = s);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _reply() async {
    final s = _s!;
    final c = TextEditingController(text: s.reply);
    var status = s.status;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Reply & status'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final x in const ['New', 'Planned', 'In Progress', 'Done', 'Not Planned'])
                  ChoiceChip(label: Text(x), selected: status == x, onSelected: (_) => set(() => status = x)),
              ]),
              const SizedBox(height: 12),
              TextField(controller: c, maxLines: 4, decoration: const InputDecoration(labelText: 'Reply (everyone sees it)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final repo = context.read<SessionController>().repo;
    final updated = await runWrite(context, () => repo.updateSuggestion(s.id, {'status': status, 'reply': c.text.trim()}), success: 'Saved');
    if (updated != null && mounted) setState(() => _s = updated);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: Text(s?.kind ?? 'Suggestion')),
      body: s == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!.message))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                _Pill(s.status, _statusColor(s.status)),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () async {
                    final repo = context.read<SessionController>().repo;
                    try {
                      final u = await repo.voteSuggestion(s.id);
                      if (mounted) setState(() => _s = Suggestion(
                            id: u.id, kind: u.kind, title: u.title, status: u.status, details: u.details, reply: u.reply,
                            votes: u.votes, voted: u.voted, by: u.by, isMine: u.isMine, at: u.at, canManage: u.canManage, files: s.files,
                          ));
                    } on ApiException catch (e) {
                      showSnack(e.message, error: true);
                    }
                  },
                  icon: Icon(s.voted ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined),
                  label: Text('${s.votes}'),
                ),
              ]),
              const SizedBox(height: 12),
              Text(s.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${s.by ?? ''} · ${fmtDayTime(s.at)}', style: const TextStyle(color: HsColors.textSecondary)),
              if (s.details != null) ...[const SizedBox(height: 12), Text(s.details!, style: const TextStyle(height: 1.35))],
              if (s.reply != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: HsColors.active, borderRadius: BorderRadius.circular(12)),
                  child: Text('Reply from the team: ${s.reply}', style: const TextStyle(color: HsColors.onPastel)),
                ),
              ],
              const SizedBox(height: 16),
              AttachmentsSection(doctype: 'Hipersign Feedback', name: s.id, canAdd: s.isMine || s.canManage, initial: s.files, title: 'Screenshots & files'),
              if (s.canManage) ...[
                const SizedBox(height: 20),
                FilledButton.icon(onPressed: _reply, icon: const Icon(Icons.reply), label: const Text('Reply / change status')),
              ],
            ]),
    );
  }
}
