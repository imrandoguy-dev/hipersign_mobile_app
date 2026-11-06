import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/activity_card.dart';
import '../../shared/widgets/common.dart';
import 'activity_detail_screen.dart';
import 'activity_form.dart';

/// Follow-ups (bottom tab) and Meetings (from More): Pending / Completed / Rescheduled.
class ActivityListScreen extends StatefulWidget {
  const ActivityListScreen({super.key, required this.meetings});

  final bool meetings;

  @override
  State<ActivityListScreen> createState() => _ActivityListScreenState();
}

class _ActivityListScreenState extends State<ActivityListScreen> with SingleTickerProviderStateMixin {
  static const _tabs = [
    ('Pending', ActivityState.pending),
    ('Completed', ActivityState.completed),
    ('Rescheduled', ActivityState.rescheduled),
  ];
  late final TabController _tabController = TabController(length: _tabs.length, vsync: this);

  /// Managers: whose list. null = mine, 'all' = everyone, or one person.
  String? _person;
  String _personName = 'Mine';
  bool _team = false;

  @override
  void initState() {
    super.initState();
    _team = context.read<SessionController>().profile?.can('team_view') ?? false;
    if (_team) {
      _person = 'all';
      _personName = 'Everyone';
    }
  }

  Future<void> _pickPerson() async {
    final repo = context.read<SessionController>().repo;
    List<MeetingPerson> people;
    try {
      people = await repo.meetingPeople();
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
      return;
    }
    if (!mounted) return;
    final me = context.read<SessionController>().profile?.user;
    final picked = await showModalBottomSheet<(String?, String)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: ListView(shrinkWrap: true, children: [
            ListTile(leading: const Icon(Icons.groups_2_outlined), title: const Text('Everyone'), onTap: () => Navigator.pop(ctx, ('all', 'Everyone'))),
            ListTile(leading: const Icon(Icons.person), title: const Text('Mine'), onTap: () => Navigator.pop(ctx, (null, 'Mine'))),
            const Divider(),
            for (final p in people.where((p) => p.id != me))
              ListTile(leading: const Icon(Icons.person_outline), title: Text(p.name), onTap: () => Navigator.pop(ctx, (p.id, p.name))),
          ]),
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _person = picked.$1;
        _personName = picked.$2;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.meetings ? 'Meetings' : 'Follow-ups';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_team)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.filter_list, size: 18),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(_personName, overflow: TextOverflow.ellipsis),
                ),
                onPressed: _pickPerson,
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: HsColors.accent,
          labelColor: HsColors.accent,
          unselectedLabelColor: HsColors.textSecondary,
          tabs: [
            for (final t in _tabs)
              Tab(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: t.$2.color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(t.$1),
                ]),
              ),
          ],
        ),
      ),
      floatingActionButton: widget.meetings
          ? FloatingActionButton.extended(
              heroTag: 'new-meeting',
              onPressed: () => openActivityForm(context, type: 'Meeting'),
              icon: const Icon(Icons.add),
              label: const Text('Meeting'),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          for (final t in _tabs)
            _ActivityTab(key: ValueKey('${t.$1}-$_person'), meetings: widget.meetings, status: t.$1, state: t.$2, person: _person),
        ],
      ),
    );
  }
}

class _ActivityTab extends StatefulWidget {
  const _ActivityTab({super.key, required this.meetings, required this.status, required this.state, this.person});

  final bool meetings;
  final String? person;
  final String status;
  final ActivityState state;

  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> with AutomaticKeepAliveClientMixin {
  List<Activity> _items = [];
  String? _next;
  DateTime? _syncedAt;
  ApiException? _error;
  bool _loading = false;
  bool _loadingMore = false;

  @override
  bool get wantKeepAlive => true;

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
    final repo = context.read<SessionController>().repo;
    final cached = repo.cachedActivities(meetings: widget.meetings, status: widget.status, person: widget.person);
    final entry = repo.cached('${widget.meetings ? 'meet' : 'fu'}:${widget.status}${widget.person == null ? '' : ':${widget.person}'}');
    setState(() {
      if (cached != null && _items.isEmpty) {
        _items = cached.items;
        _next = cached.nextCursor;
        _syncedAt = entry?.syncedAt;
      }
      _loading = true;
    });
    try {
      final page = await repo.activities(meetings: widget.meetings, status: widget.status, person: widget.person);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _next = page.nextCursor;
        _syncedAt = DateTime.now();
        _error = null;
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
      final page = await context
          .read<SessionController>()
          .repo
          .activities(meetings: widget.meetings, status: widget.status, cursor: _next, person: widget.person);
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
    super.build(context);
    final repo = context.read<SessionController>().repo;
    return RefreshIndicator(
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) _more();
          return false;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 10, bottom: 100),
          children: [
            SyncBanner(syncedAt: _syncedAt, error: _error),
            if (_loading && _items.isEmpty)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            if (!_loading && _items.isEmpty)
              EmptyState(
                icon: widget.state.icon,
                title: 'No ${widget.status.toLowerCase()} ${widget.meetings ? 'meetings' : 'follow-ups'}',
              ),
            for (final a in _items)
              ActivityCard(
                activity: a,
                // Tab colour wins here: pending = yellow-orange, completed = green, rescheduled = violet.
                stateOverride: widget.state,
                showPeople: widget.person != null,
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: a.id)));
                  _load();
                },
                onContact: (c) => repo.logContact(a.id, c).catchError((_) {}),
              ),
            if (_loadingMore) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }
}
