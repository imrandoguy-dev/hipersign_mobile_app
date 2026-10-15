import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/contact_actions.dart';
import '../calls/calls_screen.dart';
import '../recordings/recordings_screen.dart';
import 'customer_detail_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  String _kind = 'all';
  List<Party> _items = [];
  String? _next;
  bool _loading = false;
  bool _loadingMore = false;
  ApiException? _error;
  DateTime? _syncedAt;

  @override
  void initState() {
    super.initState();
    refreshTick.addListener(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    refreshTick.removeListener(_load);
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final repo = context.read<SessionController>().repo;
    final query = _q.text.trim();
    if (query.isEmpty && _items.isEmpty) {
      final cached = repo.cachedParties(_kind);
      if (cached != null) {
        setState(() {
          _items = cached.items;
          _next = cached.nextCursor;
          _syncedAt = repo.cached('cust:$_kind')?.syncedAt;
        });
      }
    }
    setState(() => _loading = true);
    try {
      final page = await repo.searchParties(query, _kind);
      if (!mounted || query != _q.text.trim()) return;
      setState(() {
        _items = page.items;
        _next = page.nextCursor;
        _error = null;
        _syncedAt = DateTime.now();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (_next == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await context.read<SessionController>().repo.searchParties(_q.text.trim(), _kind, cursor: _next);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _next = page.nextCursor;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Recent calls',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CallsScreen())),
          ),
          if (Platform.isAndroid && context.read<SessionController>().profile!.can('call_recordings'))
            IconButton(
              tooltip: 'Call recordings',
              icon: const Icon(Icons.graphic_eq),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecordingsScreen())),
            ),
        ],
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
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _q,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search name, phone or email',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _q.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _q.clear();
                              _load();
                            },
                          ),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 350), _load);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 8, children: [
                  for (final k in const [('all', 'All'), ('customer', 'Customers'), ('lead', 'Leads'), ('deal', 'Deals')])
                    ChoiceChip(
                      label: Text(k.$2),
                      selected: _kind == k.$1,
                      onSelected: (_) {
                        setState(() {
                          _kind = k.$1;
                          _items = [];
                        });
                        _load();
                      },
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              SyncBanner(syncedAt: _syncedAt, error: _error),
              if (_loading && _items.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              if (!_loading && _items.isEmpty)
                const EmptyState(icon: Icons.people_outline, title: 'No customers found'),
              for (final p in _items) _PartyTile(party: p),
              if (_loadingMore) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartyTile extends StatelessWidget {
  const _PartyTile({required this.party});
  final Party party;

  @override
  Widget build(BuildContext context) {
    final p = party;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: HsColors.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CustomerDetailScreen(doctype: p.doctype, name: p.id, title: p.name)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: switch (p.kind) {
                  'Lead' => HsColors.rescheduled,
                  'Deal' => HsColors.pending,
                  _ => HsColors.active,
                },
                foregroundColor: HsColors.onPastel,
                child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    [p.kind, if (p.subtitle != null) p.subtitle!, if (p.primaryPhone != null) p.primaryPhone!.e164 ?? p.primaryPhone!.raw]
                        .join(' - '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: HsColors.textSecondary, fontSize: 13),
                  ),
                ]),
              ),
              ContactButtons(phone: p.primaryPhone, party: p),
            ]),
          ),
        ),
      ),
    );
  }
}
