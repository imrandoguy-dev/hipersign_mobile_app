import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/auth/session.dart';
import '../activities/activity_list_screen.dart';
import '../calls/calls_screen.dart';
import '../notifications/notifications_screen.dart';
import '../recordings/recordings_screen.dart';
import '../settings/settings_screen.dart';
import '../trials/trials_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final p = session.profile!;
    void open(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(title: const Text('More', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: HsColors.card, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: HsColors.accent,
              foregroundColor: HsColors.onAccent,
              child: Text(p.fullName.isEmpty ? '?' : p.fullName[0].toUpperCase(), style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.fullName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text(p.roles.join(', '), style: const TextStyle(color: HsColors.textSecondary, fontSize: 13)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (p.can('customers'))
          _Tile(icon: Icons.call_outlined, title: 'Calls', onTap: () => open(const CallsScreen())),
        if (p.can('meetings'))
          _Tile(icon: Icons.groups_2_outlined, title: 'Meetings', onTap: () => open(const ActivityListScreen(meetings: true))),
        if (p.can('trial_booking'))
          _Tile(icon: Icons.school_outlined, title: 'Trials & training', onTap: () => open(const TrialsScreen())),
        if (Platform.isAndroid && p.can('call_recordings'))
          _Tile(icon: Icons.graphic_eq, title: 'Call recordings', onTap: () => open(const RecordingsScreen())),
        _Tile(icon: Icons.notifications_none, title: 'Notifications', onTap: () => open(const NotificationsScreen())),
        _Tile(icon: Icons.settings_outlined, title: 'Settings', onTap: () => open(const SettingsScreen())),
        const SizedBox(height: 8),
        _Tile(
          icon: Icons.logout,
          title: 'Sign out',
          danger: true,
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Sign out?'),
                content: const Text('Saved data on this phone will be cleared and notifications will stop.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
                ],
              ),
            );
            if (ok == true && context.mounted) await context.read<SessionController>().signOut();
          },
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.onTap, this.danger = false});

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: HsColors.card,
        leading: Icon(icon, color: danger ? HsColors.danger : HsColors.accent),
        title: Text(title, style: TextStyle(color: danger ? HsColors.danger : null)),
        trailing: danger ? null : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
