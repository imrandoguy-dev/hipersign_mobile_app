import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/whatsapp.dart';
import '../../shared/widgets/common.dart';

/// Pick an approved template, fill its values, send. Returns the sent message and updated chat.
Future<(WaMessage, WaChat)?> showTemplateSheet(BuildContext context, {required String phone}) {
  return showModalBottomSheet<(WaMessage, WaChat)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => _TemplateSheet(phone: phone, scroll: scroll),
    ),
  );
}

class _TemplateSheet extends StatefulWidget {
  const _TemplateSheet({required this.phone, required this.scroll});
  final String phone;
  final ScrollController scroll;

  @override
  State<_TemplateSheet> createState() => _TemplateSheetState();
}

class _TemplateSheetState extends State<_TemplateSheet> {
  List<WaTemplate>? _items;
  ApiException? _error;
  WaTemplate? _picked;
  List<TextEditingController> _values = [];
  String? _picture;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await context.read<SessionController>().repo.waTemplates(widget.phone);
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _pick(WaTemplate t) {
    for (final c in _values) {
      c.dispose();
    }
    setState(() {
      _picked = t;
      _picture = null;
      _values = List.generate(t.params, (i) {
        final c = TextEditingController(text: i < t.suggested.length ? t.suggested[i] : '');
        c.addListener(() => setState(() {}));
        return c;
      });
    });
  }

  Future<void> _choosePicture() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (x != null && mounted) setState(() => _picture = x.path);
  }

  Future<void> _send() async {
    final t = _picked!;
    final values = _values.map((c) => c.text.trim()).toList();
    if (values.any((v) => v.isEmpty)) {
      showSnack('Fill in all the values.', error: true);
      return;
    }
    if (t.needsPicture && !t.hasDefaultHeader && _picture == null) {
      showSnack('This template needs a picture.', error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      final r = await context
          .read<SessionController>()
          .repo
          .waSendTemplate(widget.phone, t.id, values, picturePath: _picture);
      if (mounted) Navigator.pop(context, r);
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _picked;
    if (t == null) return _list();
    final values = _values.map((c) => c.text).toList();
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Row(children: [
        IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _picked = null)),
        Expanded(child: Text(t.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
      ]),
      const SizedBox(height: 8),
      for (var i = 0; i < t.params; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _values[i],
            decoration: InputDecoration(
              labelText: 'Value {{${i + 1}}}',
              hintText: i < t.samples.length && t.samples[i].isNotEmpty ? 'e.g. ${t.samples[i]}' : null,
            ),
          ),
        ),
      if (t.needsPicture) ...[
        Row(children: [
          const Icon(Icons.image_outlined, color: HsColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _picture != null
                  ? 'Your picture'
                  : t.hasDefaultHeader
                      ? 'Standard picture of this template'
                      : 'This template needs a picture',
              style: TextStyle(color: _picture == null && !t.hasDefaultHeader ? HsColors.danger : null),
            ),
          ),
          TextButton(onPressed: _choosePicture, child: Text(_picture == null ? 'Choose' : 'Change')),
        ]),
        if (_picture != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_picture!), height: 160, fit: BoxFit.cover)),
          ),
      ],
      const SizedBox(height: 6),
      const Text('Preview', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFDCF3C8), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (t.headerText != null) Text(t.headerText!, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(t.preview(values), style: const TextStyle(fontSize: 14.5, height: 1.3)),
        ]),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _sending ? null : _send,
        icon: _sending
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.send),
        label: const Text('Send template'),
      ),
    ]);
  }

  Widget _list() {
    final items = _items;
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      const Text('Send a template', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const Text('Approved WhatsApp templates. They can be sent any time, also after 24 hours.',
          style: TextStyle(color: HsColors.textSecondary)),
      const SizedBox(height: 12),
      if (_error != null) SyncBanner(error: _error),
      if (items == null && _error == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
      if (items != null && items.isEmpty)
        const EmptyState(
          icon: Icons.article_outlined,
          title: 'No approved templates',
          message: 'Create templates in ERPNext (WhatsApp Templates) and wait for Meta to approve them.',
        ),
      for (final t in items ?? const <WaTemplate>[])
        Card(
          elevation: 0,
          color: HsColors.card,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            onTap: () => _pick(t),
            title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(t.body, maxLines: 3, overflow: TextOverflow.ellipsis),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (t.needsPicture) const Icon(Icons.image_outlined, size: 18, color: HsColors.textSecondary),
              if (t.category != null) Text(t.category!, style: const TextStyle(fontSize: 11, color: HsColors.textSecondary)),
            ]),
          ),
        ),
    ]);
  }
}
