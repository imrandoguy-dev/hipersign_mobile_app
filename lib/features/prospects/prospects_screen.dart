import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/nav.dart';
import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../core/callerid/call_log_sync.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/contact_actions.dart';
import '../customers/customer_detail_screen.dart';

/// A number found on Google Maps, waiting to be called.
class Prospect {
  Prospect(this.j);
  final Map<String, dynamic> j;
  String get id => j['id'].toString();
  String get name => j['name']?.toString() ?? '';
  String get phone => j['phone']?.toString() ?? '';
  String? get address => j['address']?.toString();
  String? get mapsUrl => j['maps_url']?.toString();
  String get status => j['status']?.toString() ?? 'New';
  int get attempts => (j['attempts'] as num?)?.toInt() ?? 0;
  int get lastDuration => (j['last_duration'] as num?)?.toInt() ?? 0;
  String? get lead => j['lead']?.toString();
  String? get search => j['search']?.toString();
  String? get place => j['place']?.toString();
  String? get assignedName => j['assigned_name']?.toString();
  DateTime? get lastCalled => DateTime.tryParse(j['last_called']?.toString() ?? '');

  PhoneInfo get phoneInfo {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return PhoneInfo(raw: phone, e164: phone, valid: digits.length >= 8, label: 'Mobile', telUrl: 'tel:$phone', whatsappUrl: 'https://wa.me/$digits');
  }
}

/// "New numbers": the caller's list of businesses to call. A call that connects and lasts
/// more than 5 seconds turns the number into a lead; others stay here to try again.
class ProspectsScreen extends StatefulWidget {
  const ProspectsScreen({super.key});

  @override
  State<ProspectsScreen> createState() => _ProspectsScreenState();
}

class _ProspectsScreenState extends State<ProspectsScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _tabs = [('to_call', 'To call'), ('converted', 'Became leads'), ('not_interested', 'Not interested')];
  late final TabController _tc = TabController(length: _tabs.length, vsync: this);
  final Map<String, List<Prospect>?> _items = {};
  Map<String, dynamic> _counts = {};
  String? _person; // managers: null = mine, 'all', or a caller
  String _personName = 'Mine';
  bool _manager = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _manager = context.read<SessionController>().profile?.can('prospect_search') ?? false;
    if (_manager) {
      _person = 'all';
      _personName = 'Everyone';
    }
    _tc.addListener(() {
      if (!_tc.indexIsChanging) _load(_tabs[_tc.index].$1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load('to_call'));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tc.dispose();
    super.dispose();
  }

  /// Back from a call: upload it, then refresh (a long call has made a lead).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _afterCall();
  }

  Future<void> _afterCall() async {
    final s = context.read<SessionController>();
    final user = s.profile?.user;
    if (user != null) {
      try {
        await syncCallLog(s.repo, user, force: true);
      } catch (_) {}
    }
    if (mounted) _load(_tabs[_tc.index].$1);
  }

  Future<void> _load(String tab) async {
    try {
      final d = await context.read<SessionController>().repo.prospects(tab: tab, person: _person);
      if (!mounted) return;
      setState(() {
        _error = null;
        _items[tab] = ((d['items'] as List?) ?? const []).map((e) => Prospect(Map<String, dynamic>.from(e as Map))).toList();
        _counts = Map<String, dynamic>.from((d['counts'] as Map?) ?? const {});
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _reloadAll() {
    _items.clear();
    _load(_tabs[_tc.index].$1);
  }

  Future<void> _pickPerson() async {
    List<MeetingPerson> people;
    try {
      people = await context.read<SessionController>().repo.prospectCallers();
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<(String?, String)>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(leading: const Icon(Icons.groups_2_outlined), title: const Text('Everyone'), onTap: () => Navigator.pop(ctx, ('all', 'Everyone'))),
          ListTile(leading: const Icon(Icons.person), title: const Text('Mine'), onTap: () => Navigator.pop(ctx, (null, 'Mine'))),
          const Divider(),
          for (final p in people)
            ListTile(leading: const Icon(Icons.person_outline), title: Text(p.name), onTap: () => Navigator.pop(ctx, (p.id, p.name))),
        ]),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _person = picked.$1;
        _personName = picked.$2;
      });
      _reloadAll();
    }
  }

  Future<void> _convert(Prospect p) async {
    final repo = context.read<SessionController>().repo;
    final party = await runWrite(context, () => repo.convertProspect(p.id), success: '${p.name} is now a lead');
    if (party == null || !mounted) return;
    bumpRefresh();
    _reloadAll();
    Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(doctype: party.doctype, name: party.id, title: party.name)));
  }

  Future<void> _notInterested(Prospect p) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${p.name}: not interested?'),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Reason (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Not interested')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = context.read<SessionController>().repo;
    final done = await runWrite(context, () => repo.setProspectStatus(p.id, 'Not Interested', notes: c.text.trim().isEmpty ? null : c.text.trim()).then((_) => true),
        success: 'Moved to Not interested');
    if (done == true) _reloadAll();
  }

  Future<void> _backToList(Prospect p) async {
    final repo = context.read<SessionController>().repo;
    final done = await runWrite(context, () => repo.setProspectStatus(p.id, 'New').then((_) => true), success: 'Back in To call');
    if (done == true) _reloadAll();
  }

  Widget _row(Prospect p, String tab) {
    final info = [
      if (p.attempts == 0) 'Not called yet' else '${p.attempts} call${p.attempts == 1 ? '' : 's'}${p.lastDuration > 0 ? ' · last ${p.lastDuration}s' : ' · not connected'}',
      if (p.lastCalled != null) fmtDayTime(p.lastCalled),
      if (_person != null && p.assignedName != null) p.assignedName!,
    ].join(' · ');
    return Card(
      elevation: 0,
      color: p.status == 'Not Connected' ? HsColors.pending : HsColors.card,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(p.phone, style: const TextStyle(fontSize: 13.5)),
                if (p.address != null)
                  Text(p.address!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: HsColors.textSecondary)),
                const SizedBox(height: 2),
                Text(info, style: const TextStyle(fontSize: 12, color: HsColors.textSecondary)),
              ]),
            ),
            if (tab == 'to_call') ContactButtons(phone: p.phoneInfo),
          ]),
          Wrap(spacing: 4, children: [
            if (tab == 'to_call') ...[
              TextButton.icon(onPressed: () => _convert(p), icon: const Icon(Icons.person_add_alt_1, size: 18), label: const Text('Make lead')),
              TextButton.icon(onPressed: () => _notInterested(p), icon: const Icon(Icons.block, size: 18), label: const Text('Not interested')),
            ],
            if (tab == 'converted' && p.lead != null)
              TextButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => CustomerDetailScreen(doctype: 'CRM Lead', name: p.lead!, title: p.name))),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open lead'),
              ),
            if (tab == 'not_interested')
              TextButton.icon(onPressed: () => _backToList(p), icon: const Icon(Icons.undo, size: 18), label: const Text('Call again')),
            if (p.mapsUrl != null)
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(p.mapsUrl!), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Map'),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _list(String tab) {
    final items = _items[tab];
    if (items == null) {
      return _error != null
          ? Center(child: EmptyState(icon: Icons.error_outline, title: 'Could not load', message: _error!.message))
          : const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: () => _load(tab),
      child: items.isEmpty
          ? ListView(children: [
              EmptyState(
                icon: Icons.phone_in_talk_outlined,
                title: tab == 'to_call' ? 'No new numbers to call' : 'Nothing here yet',
                message: tab == 'to_call'
                    ? (_manager ? 'Tap Find numbers to search Google Maps.' : 'Your manager will add numbers for you.')
                    : null,
              ),
            ])
          : ListView(padding: const EdgeInsets.only(top: 6, bottom: 90), children: [
              if (tab == 'to_call')
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text('A call that connects for more than 5 seconds makes it a lead automatically.',
                      style: TextStyle(fontSize: 12.5, color: HsColors.textSecondary)),
                ),
              for (final p in items) _row(p, tab),
            ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    String label((String, String) t) {
      final n = _counts[t.$1];
      return n == null ? t.$2 : '${t.$2} ($n)';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('New numbers', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_manager)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.filter_list, size: 18),
                label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 110), child: Text(_personName, overflow: TextOverflow.ellipsis)),
                onPressed: _pickPerson,
              ),
            ),
        ],
        bottom: TabBar(controller: _tc, isScrollable: true, tabs: [for (final t in _tabs) Tab(text: label(t))]),
      ),
      body: TabBarView(controller: _tc, children: [for (final t in _tabs) _list(t.$1)]),
      floatingActionButton: _manager
          ? FloatingActionButton.extended(
              onPressed: () async {
                final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const FindNumbersScreen()));
                if (added == true) _reloadAll();
              },
              icon: const Icon(Icons.travel_explore),
              label: const Text('Find numbers'),
            )
          : null,
    );
  }
}

/// Managers: search Google Maps for a kind of business in a place, and give the new numbers
/// to callers.
class FindNumbersScreen extends StatefulWidget {
  const FindNumbersScreen({super.key});

  @override
  State<FindNumbersScreen> createState() => _FindNumbersScreenState();
}

class _FindNumbersScreenState extends State<FindNumbersScreen> {
  final _business = TextEditingController();
  final _places = TextEditingController();
  final _count = TextEditingController(text: '70');
  List<MeetingPerson>? _callers;
  final Set<String> _picked = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final c = await context.read<SessionController>().repo.prospectCallers();
        if (mounted) setState(() => _callers = c);
      } on ApiException catch (e) {
        showSnack(e.message, error: true);
        if (mounted) setState(() => _callers = const []);
      }
    });
  }

  @override
  void dispose() {
    _business.dispose();
    _places.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final business = _business.text.trim(), places = _places.text.trim();
    final count = int.tryParse(_count.text.trim()) ?? 70;
    if (business.isEmpty) return showMissing(context, 'Business type', 'Type what kind of businesses to find, e.g. solar companies.');
    if (places.isEmpty) return showMissing(context, 'Place', 'Type the place, e.g. Kochi.');
    if (_picked.isEmpty) return showMissing(context, 'Callers', 'Choose who will call these numbers.');
    setState(() => _busy = true);
    try {
      final r = await context.read<SessionController>().repo.findProspects(business, places, count, _picked.toList());
      if (!mounted) return;
      final found = (r['found'] as num?)?.toInt() ?? 0;
      final per = ((r['per_caller'] as List?) ?? const []).map((e) => '${(e as Map)['name']}: ${e['count']}').join('\n');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(found == 0 ? 'No new numbers' : '$found new numbers added'),
          content: Text([
            if (found > 0) per,
            if ((r['skipped_known'] as num? ?? 0) > 0) '${r['skipped_known']} were already in ERP (skipped).',
            if (r['short'] == true && found > 0) 'Google had fewer new results than asked. Try another place or business type for more.',
            if (found == 0) 'Everything Google found is already in ERP. Try another place or business type.',
          ].join('\n\n')),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      if (mounted && found > 0) Navigator.pop(context, true);
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final callers = _callers;
    return Scaffold(
      appBar: AppBar(title: const Text('Find new numbers')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _business,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'What businesses', hintText: 'e.g. solar companies, builders'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _places,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Where', hintText: 'e.g. Kochi, Thrissur, Kakkanad'),
        ),
        const SizedBox(height: 4),
        const Text('Separate several with commas.', style: TextStyle(fontSize: 12, color: HsColors.textSecondary)),
        const SizedBox(height: 12),
        TextField(controller: _count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'How many numbers')),
        const SizedBox(height: 16),
        const Text('Give them to', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const Text('Shared out evenly.', style: TextStyle(fontSize: 12, color: HsColors.textSecondary)),
        if (callers == null)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else if (callers.isEmpty)
          const Padding(padding: EdgeInsets.all(8), child: Text('No cold callers or sales people found. Give the role in ERP first.'))
        else
          for (final c in callers)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _picked.contains(c.id),
              title: Text(c.name),
              onChanged: (v) => setState(() => v == true ? _picked.add(c.id) : _picked.remove(c.id)),
            ),
        const SizedBox(height: 8),
        const Text('Numbers already in ERP (customers, leads, contacts, earlier searches) are skipped.',
            style: TextStyle(fontSize: 12.5, color: HsColors.textSecondary)),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _busy ? null : _find,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.travel_explore),
            label: Text(_busy ? 'Searching Google Maps…' : 'Find numbers'),
          ),
        ),
      ),
    );
  }
}
