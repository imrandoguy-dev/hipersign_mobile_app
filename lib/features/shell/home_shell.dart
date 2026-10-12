import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/auth/session.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/updates/update_service.dart';
import '../activities/activity_form.dart';
import '../activities/activity_list_screen.dart';
import '../calendar/calendar_screen.dart';
import '../customers/customers_screen.dart';
import '../trials/book_trial_screen.dart';
import 'more_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifications = NotificationService.instance;
    notifications.onOpenRoute = (route) => navigatorKey.currentState?.pushNamed(route);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = notifications.takePendingRoute();
      if (pending != null) navigatorKey.currentState?.pushNamed(pending);
      _checkForUpdate();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.instance.onOpenRoute = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<SessionController>().refreshProfile(); // picks up role changes (FR-005)
      bumpRefresh();
      _checkForUpdate();
    }
  }

  void _checkForUpdate() {
    final api = context.read<SessionController>().api;
    if (api != null) UpdateService.instance.autoCheck(context, api);
  }

  void _openQuickActions() {
    final p = context.read<SessionController>().profile!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (p.can('create_activity'))
            ListTile(
              leading: const Icon(Icons.phone_callback_outlined),
              title: const Text('New follow-up'),
              onTap: () {
                Navigator.pop(sheetContext);
                openActivityForm(context, type: 'Follow-up');
              },
            ),
          if (p.can('create_activity'))
            ListTile(
              leading: const Icon(Icons.groups_2_outlined),
              title: const Text('Schedule meeting'),
              onTap: () {
                Navigator.pop(sheetContext);
                openActivityForm(context, type: 'Meeting');
              },
            ),
          if (p.can('trial_booking'))
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('Book a trial'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const BookTrialScreen()));
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final profile = session.profile!;
    if (!profile.workspaces.contains('sales')) {
      return _NoWorkspace(name: profile.fullName);
    }
    final pages = <Widget>[
      const CalendarScreen(),
      const ActivityListScreen(meetings: false),
      const CustomersScreen(),
      const MoreScreen(),
    ];
    // Bar positions: 0 Calendar, 1 Follow-ups, [2 = plus], 3 Customers, 4 More
    final barIndex = _tab >= 2 ? _tab + 1 : _tab;
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        tooltip: 'Quick actions',
        backgroundColor: HsColors.accent,
        foregroundColor: HsColors.onPastel,
        shape: const CircleBorder(),
        onPressed: _openQuickActions,
        child: const Icon(Icons.add, size: 30),
      ),
      bottomNavigationBar: BottomAppBar(
        color: HsColors.card,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        padding: EdgeInsets.zero,
        height: 68,
        child: Row(children: [
          _NavItem(icon: Icons.calendar_month, label: 'Calendar', selected: barIndex == 0, onTap: () => setState(() => _tab = 0)),
          _NavItem(icon: Icons.checklist_rtl, label: 'Follow-ups', selected: barIndex == 1, onTap: () => setState(() => _tab = 1)),
          const Expanded(child: SizedBox()),
          _NavItem(icon: Icons.people_alt_outlined, label: 'Customers', selected: barIndex == 3, onTap: () => setState(() => _tab = 2)),
          _NavItem(icon: Icons.more_horiz, label: 'More', selected: barIndex == 4, onTap: () => setState(() => _tab = 3)),
        ]),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? HsColors.accent : HsColors.textSecondary;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ]),
        ),
      ),
    );
  }
}

class _NoWorkspace extends StatelessWidget {
  const _NoWorkspace({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.lock_person_outlined, size: 56, color: HsColors.accent),
            const SizedBox(height: 16),
            Text('Hi $name', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Your account does not have a mobile workspace yet. Ask your administrator to give you a Hipersign role (for example "Hipersign Sales") in ERPNext.',
              textAlign: TextAlign.center,
              style: TextStyle(color: HsColors.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.read<SessionController>().refreshProfile(),
              child: const Text('Check again'),
            ),
            TextButton(
              onPressed: () => context.read<SessionController>().signOut(),
              child: const Text('Sign out'),
            ),
          ]),
        ),
      ),
    );
  }
}
