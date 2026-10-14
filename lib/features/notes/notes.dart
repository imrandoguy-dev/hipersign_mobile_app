import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';

String _when(DateTime? d) {
  if (d == null) return '';
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Today ${DateFormat.jm().format(d)}';
  return DateFormat('d MMM yyyy, h:mm a').format(d);
}

/// Write or edit a note. Returns true when something was saved or deleted.
Future<bool> openNoteEditor(BuildContext context, {required String doctype, required String name, required String partyName, Note? note}) async {
  final saved = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _NoteEditor(doctype: doctype, name: name, partyName: partyName, note: note),
    ),
  );
  return saved == true;
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({required this.doctype, required this.name, required this.partyName, this.note});

  final String doctype;
  final String name;
  final String partyName;
  final Note? note;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController _text = TextEditingController(text: widget.note?.text ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      showSnack('Write something first.', error: true);
      return;
    }
    setState(() => _saving = true);
    final repo = context.read<SessionController>().repo;
    try {
      if (widget.note == null) {
        await repo.addPartyNote(widget.doctype, widget.name, text);
      } else {
        await repo.updatePartyNote(widget.note!.id, text);
      }
      if (mounted) Navigator.pop(context, true);
      showSnack('Note saved');
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this note?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HsColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = context.read<SessionController>().repo;
    try {
      await repo.deletePartyNote(widget.note!.id);
      if (mounted) Navigator.pop(context, true);
      showSnack('Note deleted');
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.note != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit note' : 'New note'),
        actions: [
          if (editing)
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, color: HsColors.danger), onPressed: _delete),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _saving
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : TextButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.partyName, style: const TextStyle(color: HsColors.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Expanded(
            child: TextField(
              controller: _text,
              autofocus: !editing,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'What was discussed, requirements, next steps...',
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Saved to ERPNext - visible in Frappe CRM\'s Notes too.',
              style: TextStyle(fontSize: 12, color: HsColors.textSecondary)),
        ]),
      ),
    );
  }
}

/// One note as a card. Tap to read in full / edit.
class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note, required this.onTap, this.maxLines = 4});

  final Note note;
  final VoidCallback onTap;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final showTitle = note.title.isNotEmpty && !note.text.startsWith(note.title.replaceAll('...', ''));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: HsColors.warningBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (showTitle)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(note.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              Text(note.text, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Text(
                [
                  if (note.ownerName != null) note.ownerName!,
                  _when(note.created),
                  if (note.fromLead) 'from the lead',
                ].join('  ·  '),
                style: const TextStyle(fontSize: 12, color: HsColors.textSecondary),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Opens a note: full text; editable when it's yours (or you're a manager).
Future<bool> openNote(BuildContext context, {required String doctype, required String name, required String partyName, required Note note}) {
  if (note.canEdit) return openNoteEditor(context, doctype: doctype, name: name, partyName: partyName, note: note);
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(note.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: HsColors.navy)),
            const SizedBox(height: 10),
            SelectableText(note.text, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 12),
            Text('${note.ownerName ?? ''}  ·  ${_when(note.created)}',
                style: const TextStyle(fontSize: 12, color: HsColors.textSecondary)),
          ]),
        ),
      ),
    ),
  ).then((_) => false);
}

/// All notes of a customer / lead / deal.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.doctype, required this.name, required this.partyName});

  final String doctype;
  final String name;
  final String partyName;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Note>? _notes;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final n = await context.read<SessionController>().repo.partyNotes(widget.doctype, widget.name);
      if (mounted) {
        setState(() {
          _notes = n;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _add() async {
    if (await openNoteEditor(context, doctype: widget.doctype, name: widget.name, partyName: widget.partyName)) _load();
  }

  @override
  Widget build(BuildContext context) {
    final notes = _notes;
    return Scaffold(
      appBar: AppBar(title: Text('Notes · ${widget.partyName}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('Add note'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 96), children: [
          if (_error != null) SyncBanner(error: _error),
          if (notes == null && _error == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          if (notes != null && notes.isEmpty)
            const EmptyState(icon: Icons.sticky_note_2_outlined, title: 'No notes yet', message: 'Tap "Add note" to write the first one.'),
          for (final n in notes ?? const <Note>[])
            NoteCard(
              note: n,
              maxLines: null,
              onTap: () async {
                if (await openNote(context, doctype: widget.doctype, name: widget.name, partyName: widget.partyName, note: n)) {
                  _load();
                }
              },
            ),
        ]),
      ),
    );
  }
}
