import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';

/// Full-screen search to choose a Customer or CRM Lead.
Future<Party?> pickParty(BuildContext context, {String kind = 'all'}) {
  return Navigator.push<Party>(
    context,
    MaterialPageRoute(builder: (_) => _PartyPicker(kind: kind), fullscreenDialog: true),
  );
}

class _PartyPicker extends StatefulWidget {
  const _PartyPicker({required this.kind});
  final String kind;

  @override
  State<_PartyPicker> createState() => _PartyPickerState();
}

class _PartyPickerState extends State<_PartyPicker> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Party> _items = [];
  bool _loading = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final page = await context.read<SessionController>().repo.searchParties(_q.text.trim(), widget.kind);
      if (mounted) setState(() {
        _items = page.items;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _q,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search name, phone or email', prefixIcon: Icon(Icons.search)),
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), _search);
          },
        ),
      ),
      body: ListView(children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) SyncBanner(error: _error),
        if (!_loading && _items.isEmpty) const EmptyState(icon: Icons.search_off, title: 'No matches'),
        for (final p in _items)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: HsColors.cardHigh,
              child: Icon(p.kind == 'Lead' ? Icons.person_add_alt : Icons.business, size: 20),
            ),
            title: Text(p.name),
            subtitle: Text([p.kind, if (p.subtitle != null) p.subtitle!, if (p.primaryPhone != null) p.primaryPhone!.e164 ?? p.primaryPhone!.raw].join(' - ')),
            onTap: () => Navigator.pop(context, p),
          ),
      ]),
    );
  }
}
