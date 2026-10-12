import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/notifications/reminder_planner.dart';
import '../../core/updates/update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _prefs;
  bool? _permission;
  bool _exact = true;
  String _phoneMode = 'auto';
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<SessionController>();
    final service = NotificationService.instance;
    final perm = await service.permissionGranted();
    final exact = await service.canScheduleExact();
    if (!mounted) return;
    setState(() {
      _permission = perm;
      _exact = exact;
      _phoneMode = session.cache.getPref(phoneRemindersPref) ?? 'auto';
    });
    try {
      final p = await session.repo.preferences();
      await session.cache.setPref(reminderMinutesPref, '${p['reminder_minutes']}');
      if (mounted) setState(() => _prefs = p);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save(Map<String, dynamic> change) async {
    final session = context.read<SessionController>();
    final before = Map<String, dynamic>.from(_prefs ?? {});
    setState(() => _prefs = {...?_prefs, ...change});
    try {
      await session.repo.savePreferences(change);
      if (change.containsKey('reminder_minutes')) {
        await session.cache.setPref(reminderMinutesPref, '${change['reminder_minutes']}');
        await planLocalReminders(session.repo);
      }
      showSnack('Saved');
    } on ApiException catch (e) {
      if (mounted) setState(() => _prefs = before); // never show a change the server didn't accept
      showSnack(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final service = NotificationService.instance;
    final p = _prefs;
    final pushState = !service.firebaseReady
        ? 'Not configured in this build'
        : (service.pushToken == null ? 'Not registered (check permission / internet)' : 'Active on this phone');
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const _Header('Notifications'),
        _Card(children: [
          ListTile(
            leading: Icon(_permission == false ? Icons.notifications_off_outlined : Icons.notifications_active_outlined,
                color: _permission == false ? HsColors.danger : HsColors.completed),
            title: const Text('Notification permission'),
            subtitle: Text(_permission == null ? 'Unknown' : (_permission! ? 'Allowed' : 'Blocked - you will miss reminders')),
            trailing: _permission == false
                ? TextButton(
                    onPressed: () async {
                      final ok = await service.requestPermission();
                      if (!ok) showSnack('Enable notifications for Hipersign in your phone settings.', error: true);
                      _load();
                    },
                    child: const Text('Allow'),
                  )
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Push notifications'),
            subtitle: Text(pushState),
          ),
          if (Platform.isAndroid && !_exact)
            ListTile(
              leading: const Icon(Icons.alarm_on_outlined),
              title: const Text('Exact reminder times'),
              subtitle: const Text('Allow "Alarms & reminders" so phone reminders fire on time.'),
              trailing: TextButton(
                onPressed: () async {
                  await service.requestExactAlarms();
                  _load();
                },
                child: const Text('Allow'),
              ),
            ),
        ]),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!.message, style: const TextStyle(color: HsColors.danger))),
        if (p != null) ...[
          const _Header('What to notify me about'),
          _Card(children: [
            SwitchListTile(
              title: const Text('New and changed assignments'),
              value: p['notify_assignments'] == true,
              onChanged: (v) => _save({'notify_assignments': v}),
            ),
            SwitchListTile(
              title: const Text('Reminders before activities'),
              value: p['notify_reminders'] == true,
              onChanged: (v) => _save({'notify_reminders': v}),
            ),
            SwitchListTile(
              title: const Text('Trial booking updates'),
              value: p['notify_trials'] == true,
              onChanged: (v) => _save({'notify_trials': v}),
            ),
            ListTile(
              title: const Text('Remind me'),
              trailing: DropdownButton<int>(
                value: (p['reminder_minutes'] as num?)?.toInt() ?? 15,
                underline: const SizedBox(),
                items: [
                  for (final m in ((p['reminder_choices'] as List?) ?? const [0, 5, 10, 15, 30, 60, 120]).map((e) => (e as num).toInt()))
                    DropdownMenuItem(value: m, child: Text(m == 0 ? 'At start time' : (m < 60 ? '$m min before' : '${m ~/ 60} h before'))),
                ],
                onChanged: (v) {
                  if (v != null) _save({'reminder_minutes': v});
                },
              ),
            ),
          ]),
        ],
        const _Header('Backup reminders on this phone'),
        _Card(children: [
          RadioGroup<String>(
            groupValue: _phoneMode,
            onChanged: (v) async {
              if (v == null) return;
              setState(() => _phoneMode = v);
              await session.cache.setPref(phoneRemindersPref, v);
              await planLocalReminders(session.repo);
            },
            child: const Column(children: [
              RadioListTile<String>(
                value: 'auto',
                title: Text('Automatic'),
                subtitle: Text('Only when push notifications are not working'),
              ),
              RadioListTile<String>(value: 'on', title: Text('Always'), subtitle: Text('You may get some reminders twice')),
              RadioListTile<String>(value: 'off', title: Text('Off')),
            ]),
          ),
        ]),
        if (Platform.isAndroid) ...[
          const _Header('If notifications arrive late'),
          const _Card(children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Some phones (Xiaomi, Redmi, Oppo, Vivo, Realme, OnePlus, Samsung) stop apps in the background. '
                'Open phone Settings > Apps > Hipersign and:\n'
                '- Battery: set to "No restrictions" / "Unrestricted"\n'
                '- Turn on "Autostart" (Xiaomi, Oppo, Vivo, Realme)\n'
                '- Notifications: allow all, including "Hipersign alerts"\n'
                '- Lock the app in recent apps (pull down on its card)',
                style: TextStyle(height: 1.4),
              ),
            ),
          ]),
        ],
        const _Header('About'),
        _Card(children: [
          ListTile(title: const Text('Signed in as'), subtitle: Text(session.profile?.user ?? '-')),
          ListTile(title: const Text('Server'), subtitle: Text(session.server ?? '-')),
          const _VersionTile(),
        ]),
        const SizedBox(height: 40),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(text, style: const TextStyle(color: HsColors.accent, fontWeight: FontWeight.w700)),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: HsColors.card, borderRadius: BorderRadius.circular(18)),
        child: Column(children: children),
      );
}

class _VersionTile extends StatefulWidget {
  const _VersionTile();

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  String _version = appVersion;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    UpdateService.instance.packageInfo().then((p) {
      if (mounted) setState(() => _version = '${p.version} (build ${p.buildNumber})');
    }).catchError((_) {});
  }

  Future<void> _check() async {
    final api = context.read<SessionController>().api;
    if (api == null) return;
    setState(() => _checking = true);
    try {
      final info = await UpdateService.instance.check(api);
      if (!mounted) return;
      if (info.available) {
        await UpdateService.instance.showUpdatePrompt(context, api, info);
      } else {
        showSnack(info.reason ?? 'You have the latest version.');
      }
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('App version'),
      subtitle: Text(_version),
      trailing: Platform.isAndroid
          ? (_checking
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(onPressed: _check, child: const Text('Check for updates')))
          : null,
    );
  }
}
