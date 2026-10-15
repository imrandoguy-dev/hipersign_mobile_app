import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';

/// Edit a customer / lead / deal. The fields (and their choices) come from the server, so
/// each site shows what it has. Returns true when something was saved.
Future<bool> openEditParty(BuildContext context, Party party) async {
  final saved = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => EditPartyScreen(party: party), fullscreenDialog: true),
  );
  return saved == true;
}

class EditPartyScreen extends StatefulWidget {
  const EditPartyScreen({super.key, required this.party});

  final Party party;

  @override
  State<EditPartyScreen> createState() => _EditPartyScreenState();
}

class _EditPartyScreenState extends State<EditPartyScreen> {
  List<EditField>? _fields;
  ApiException? _error;
  bool _saving = false;
  final Map<String, String?> _values = {};
  final Map<String, TextEditingController> _text = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final f = await context.read<SessionController>().repo.editForm(widget.party.doctype, widget.party.id);
      if (!mounted) return;
      setState(() {
        _fields = f;
        for (final x in f) {
          _values[x.key] = x.value;
          if (x.type != 'select' && x.type != 'date') _text[x.key] = TextEditingController(text: x.value ?? '');
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String? _current(EditField f) {
    final c = _text[f.key];
    if (c != null) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }
    return _values[f.key];
  }

  bool _visible(EditField f) => f.showIfKey == null || f.showIfValues.contains(_valueOf(f.showIfKey!));

  String? _valueOf(String key) {
    final f = _fields?.where((x) => x.key == key).firstOrNull;
    return f == null ? null : _current(f);
  }

  Future<void> _save() async {
    final fields = _fields;
    if (fields == null) return;
    final changed = <String, dynamic>{};
    for (final f in fields) {
      if (!_visible(f)) continue;
      final v = _current(f);
      if (f.required && v == null) {
        showSnack('${f.label} is required', error: true);
        return;
      }
      if (v != (f.value == null || f.value!.isEmpty ? null : f.value)) changed[f.key] = v;
    }
    if (changed.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<SessionController>().repo.updateParty(widget.party.doctype, widget.party.id, changed);
      if (!mounted) return;
      showSnack('Saved to ERP');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _input(EditField f) {
    final label = f.required ? '${f.label} *' : f.label;
    switch (f.type) {
      case 'select':
        final options = [...f.options];
        final v = _values[f.key];
        if (v != null && !options.contains(v)) options.insert(0, v);
        return DropdownButtonFormField<String>(
          initialValue: v,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            if (!f.required) const DropdownMenuItem<String>(value: null, child: Text('-')),
            for (final o in options) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (x) => setState(() => _values[f.key] = x),
        );
      case 'date':
        final v = _values[f.key];
        final d = v == null ? null : DateTime.tryParse(v);
        return InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Row(children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: d ?? now,
                    firstDate: DateTime(now.year - 5),
                    lastDate: DateTime(now.year + 5),
                  );
                  if (picked != null) {
                    setState(() => _values[f.key] =
                        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
                  }
                },
                child: Text(d == null ? 'Choose a date' : fmtDay(d),
                    style: TextStyle(color: d == null ? HsColors.textSecondary : null)),
              ),
            ),
            if (d != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => setState(() => _values[f.key] = null),
              ),
          ]),
        );
      default:
        return TextField(
          controller: _text[f.key],
          maxLines: f.type == 'multiline' ? 3 : 1,
          keyboardType: switch (f.type) {
            'phone' => TextInputType.phone,
            'email' => TextInputType.emailAddress,
            'number' => const TextInputType.numberWithOptions(decimal: true),
            'multiline' => TextInputType.multiline,
            _ => TextInputType.text,
          },
          textCapitalization:
              f.type == 'text' || f.type == 'multiline' ? TextCapitalization.sentences : TextCapitalization.none,
          decoration: InputDecoration(labelText: label),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = _fields;
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${widget.party.kind.toLowerCase()}'),
        actions: [
          TextButton(
            onPressed: _saving || fields == null ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: fields == null
          ? (_error == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: EmptyState(
                    icon: Icons.error_outline,
                    title: 'Could not open the form',
                    message: _error!.message,
                    action: FilledButton(onPressed: _load, child: const Text('Try again')),
                  ),
                ))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(widget.party.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (final f in fields)
                if (_visible(f)) Padding(padding: const EdgeInsets.only(bottom: 12), child: _input(f)),
              const SizedBox(height: 24),
            ]),
    );
  }
}
