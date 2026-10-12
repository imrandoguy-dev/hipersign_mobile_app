import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
          for (final t in _tabs) _ActivityTab(meetings: widget.meetings, status: t.$1, state: t.$2),
        ],
      ),
    );
  }
}

class _ActivityTab extends StatefulWidget {
  const _ActivityTab({required this.meetings, required this.status, required this.state});

  final bool meetings;
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
    final cached = repo.cachedActivities(meetings: widget.meetings, status: widget.status);
    final entry = repo.cached('${widget.meetings ? 'meet' : 'fu'}:${widget.status}');
    setState(() {
      if (cached != null && _items.isEmpty) {
        _items = cached.items;
        _next = cached.nextCursor;
        _syncedAt = entry?.syncedAt;
      }
      _loading = true;
    });
    try {
      final page = await repo.activities(meetings: widget.meetings, status: widget.status);
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
          .activities(meetings: widget.meetings, status: widget.status, cursor: _next);
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
