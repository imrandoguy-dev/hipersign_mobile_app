import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotice> _items = [];
  bool _loading = true;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await context.read<SessionController>().repo.notifications();
      if (mounted) setState(() {
        _items = items;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _icon(String title) {
    final t = title.toLowerCase();
    if (t.contains('trial')) return Icons.school_outlined;
    if (t.contains('reminder') || t.contains('upcoming')) return Icons.alarm;
    if (t.contains('rescheduled')) return Icons.update;
    return Icons.assignment_ind_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          if (_error != null) SyncBanner(error: _error),
          if (_loading && _items.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          if (!_loading && _items.isEmpty)
            const EmptyState(icon: Icons.notifications_none, title: 'No notifications yet'),
          for (final n in _items)
            ListTile(
              leading: CircleAvatar(backgroundColor: HsColors.card, child: Icon(_icon(n.title), color: HsColors.accent, size: 20)),
              title: Text(n.title),
              subtitle: Text([
                if (n.body != null) n.body!,
                ago(n.at),
                if (n.problem == 'NO_DEVICE' || n.problem == 'NO_TOKEN') 'not delivered to a phone',
              ].join(' - ')),
              onTap: isDeepLink(n.route) ? () => Navigator.pushNamed(context, n.route!) : null,
            ),
        ]),
      ),
    );
  }
}
