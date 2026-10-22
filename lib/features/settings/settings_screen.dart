import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../core/callerid/caller_directory.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/notifications/reminder_planner.dart';
import '../../core/phone/direct_call.dart';
import '../../core/updates/update_service.dart';
import '../../core/widget/home_widget.dart';
import '../../shared/widgets/reminder_picker.dart';
import '../recordings/recordings_screen.dart';

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
      if (p['reminder_offsets'] is List) {
        await session.cache.setPref(reminderOffsetsPref, (p['reminder_offsets'] as List).join(','));
      }
      if (p['alarm_high_priority'] != null) {
        await session.cache.setPref(alarmHighPref, p['alarm_high_priority'] == true ? '1' : '0');
      }
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
      await session.repo.savePreferences({
        for (final e in change.entries)
          if (!e.key.endsWith('_list')) e.key: e.value,
      });
      if (change.containsKey('reminder_minutes')) {
        await session.cache.setPref(reminderMinutesPref, '${change['reminder_minutes']}');
      }
      if (change.containsKey('reminder_offsets')) {
        await session.cache.setPref(reminderOffsetsPref, change['reminder_offsets'].toString());
      }
      if (change.containsKey('alarm_high_priority')) {
        await session.cache.setPref(alarmHighPref, change['alarm_high_priority'] == true ? '1' : '0');
      }
      if (change.keys.any((k) => k.startsWith('reminder') || k == 'alarm_high_priority')) {
        await planLocalReminders(session.repo);
      }
      showSnack('Saved');
    } on ApiException catch (e) {
      if (mounted) setState(() => _prefs = before); // never show a change the server didn't accept
      showSnack(e.message, error: true);
    }
  }

  List<int> _offsets(Map<String, dynamic> p) {
    final l = p['reminder_offsets_list'] ?? p['reminder_offsets'];
    if (l is List) return l.map((e) => (e as num).toInt()).toList();
    if (l is String) return parseOffsets(l);
    final m = (p['reminder_minutes'] as num?)?.toInt() ?? 15;
    return {m, 0}.toList();
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
            if (p.containsKey('notify_development') && (session.profile?.can('development') ?? false))
              SwitchListTile(
                title: const Text('Development tasks'),
                subtitle: const Text('New work, reminders before the deadline, deadline crossed'),
                value: p['notify_development'] == true,
                onChanged: (v) => _save({'notify_development': v}),
              ),
            if (p.containsKey('notify_tasks'))
              SwitchListTile(
                title: const Text('Tasks'),
                subtitle: const Text('New tasks, reminders before the deadline, deadline crossed'),
                value: p['notify_tasks'] == true,
                onChanged: (v) => _save({'notify_tasks': v}),
              ),
            if (p.containsKey('notify_whatsapp'))
              SwitchListTile(
                title: const Text('New WhatsApp messages'),
                subtitle: const Text('From your customers, and from numbers not in ERPNext yet'),
                value: p['notify_whatsapp'] == true,
                onChanged: (v) => _save({'notify_whatsapp': v}),
              ),
            ListTile(
              leading: const Icon(Icons.alarm_outlined),
              title: const Text('Remind me'),
              subtitle: Text(describeReminders(_offsets(p))),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final r = await pickReminders(context, initial: _offsets(p));
                if (r != null && r.offsets.isNotEmpty) {
                  _save({'reminder_offsets': r.offsets.join(','), 'reminder_offsets_list': r.offsets});
                }
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined, color: HsColors.danger),
              title: const Text('High priority rings like an alarm'),
              subtitle: const Text('Alarm sound and vibration that keep going until you open or swipe it'),
              value: p['alarm_high_priority'] != false,
              onChanged: (v) => _save({'alarm_high_priority': v}),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.volume_up_outlined, size: 18),
                  label: const Text('Test the alarm'),
                  onPressed: () => NotificationService.instance.testAlarm(),
                ),
              ),
            ),
          ]),
        ],
        if (Platform.isAndroid) ...[
          const _Header('Home screen'),
          _Card(children: [
            ListTile(
              leading: const Icon(Icons.widgets_outlined),
              title: const Text('Calendar widget'),
              subtitle: const Text("Today's follow-ups and meetings on your home screen - pending first, done at the bottom."),
              trailing: FilledButton(
                onPressed: () async {
                  await updateHomeWidget(session.repo);
                  final ok = await pinHomeWidget();
                  if (!ok) {
                    showSnack('Long-press your home screen > Widgets > Hipersign, and drag "Hipersign calendar" to the screen.');
                  }
                },
                child: const Text('Add'),
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
        if (Platform.isAndroid && (session.profile?.can('customers') ?? false)) ...[
          const _Header('Caller pop-up'),
          const _CallerIdCard(),
        ],
        if (Platform.isAndroid && (session.profile?.can('customers') ?? false)) ...[
          const _Header('Work SIM'),
          const _WorkSimCard(),
        ],
        if (Platform.isAndroid && (session.profile?.can('call_recordings') ?? false)) ...[
          const _Header('Call recordings'),
          _Card(children: [
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: const Text('My call recordings'),
              subtitle: const Text('Calls made from Hipersign, saved to the customer in ERP'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecordingsScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('How to set up call recording'),
              onTap: () => showRecordingHelp(context),
            ),
          ]),
        ],
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

/// Caller pop-up: shows the ERPNext customer / lead / deal over the call screen.
class _WorkSimCard extends StatefulWidget {
  const _WorkSimCard();

  @override
  State<_WorkSimCard> createState() => _WorkSimCardState();
}

class _WorkSimCardState extends State<_WorkSimCard> with WidgetsBindingObserver {
  SimSetup? _setup;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(); // back from phone settings
  }

  Future<void> _refresh() async {
    final s = await simSetup();
    if (mounted) {
      setState(() {
        _setup = s;
        _loaded = true;
      });
    }
  }

  Future<void> _toggle(String id, bool on) async {
    final selected = {...?_setup?.selected};
    on ? selected.add(id) : selected.remove(id);
    await setWorkSims(selected);
    await _refresh();
  }

  static const _note = TextStyle(fontSize: 12.5, color: HsColors.textSecondary, height: 1.4);

  @override
  Widget build(BuildContext context) {
    final s = _setup;
    if (!_loaded) return const _Card(children: [ListTile(title: Text('Checking...'))]);
    if (s == null) return const _Card(children: [ListTile(title: Text('Not available on this phone'))]);
    final sims = s.sims;
    if (sims == null) {
      return _Card(children: [
        ListTile(
          leading: const Icon(Icons.sim_card_outlined, color: HsColors.warning),
          title: const Text('Choose your work SIM'),
          subtitle: const Text('Allow phone access so Hipersign can see the SIMs in this phone'),
          trailing: TextButton(
            onPressed: () async {
              final r = await requestCallerIdPermissions();
              if (r != null && !r.phone) {
                showSnack('Allow "Phone" and "Call logs" for Hipersign in phone settings.', error: true);
                await openAppSettings();
              }
              _refresh();
            },
            child: const Text('Allow'),
          ),
        ),
      ]);
    }
    if (sims.length <= 1) {
      return _Card(children: [
        ListTile(
          leading: const Icon(Icons.sim_card_outlined),
          title: Text(sims.isEmpty ? 'No SIM found' : sims.first.title),
          subtitle: const Text('Only one SIM in this phone - its calls to customers, leads and deals count as work calls.'),
        ),
      ]);
    }
    // A chosen SIM that is no longer in the phone (SIM swapped).
    final missing = s.selected.where((id) => !sims.any((x) => x.id == id)).toList();
    final chosen = sims.where((x) => s.selected.contains(x.id)).toList();
    return _Card(children: [
      for (final sim in sims)
        CheckboxListTile(
          secondary: const Icon(Icons.sim_card_outlined),
          title: Text(sim.title),
          subtitle: Text(s.selected.contains(sim.id) ? 'Work SIM' : (s.selected.isEmpty ? 'Counted (no work SIM chosen)' : 'Personal - ignored')),
          value: s.selected.contains(sim.id),
          onChanged: (v) => _toggle(sim.id, v ?? false),
        ),
      if (missing.isNotEmpty)
        ListTile(
          leading: const Icon(Icons.warning_amber_rounded, color: HsColors.warning),
          title: const Text('A chosen work SIM is not in this phone'),
          subtitle: const Text('Tick the SIM you use for work now.'),
          trailing: TextButton(
            onPressed: () async {
              await setWorkSims(s.selected.where((id) => !missing.contains(id)));
              _refresh();
            },
            child: const Text('Clear'),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: Text(
          s.selected.isEmpty
              ? 'No work SIM chosen: calls on every SIM are recorded, uploaded and counted. Tick your work SIM to keep personal calls out.'
              : 'Only calls on the ticked SIM${chosen.length == 1 ? '' : 's'} are recorded, uploaded, counted in reports and '
                  'get the after-call screen. Calls on other SIMs stay on the phone.'
                  '${chosen.length == 1 ? ' Calls you place from Hipersign go out on ${chosen.first.title.split(' - ').first}.' : ''}',
          style: _note,
        ),
      ),
    ]);
  }
}

class _CallerIdCard extends StatefulWidget {
  const _CallerIdCard();

  @override
  State<_CallerIdCard> createState() => _CallerIdCardState();
}

class _CallerIdCardState extends State<_CallerIdCard> with WidgetsBindingObserver {
  CallerIdStatus? _status;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(); // back from phone settings
  }

  Future<void> _refresh() async {
    final s = await callerIdStatus();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      await syncCallerDirectory(context.read<SessionController>().repo, force: true);
      showSnack('Caller names updated');
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (s == null) return const _Card(children: [ListTile(title: Text('Checking...'))]);
    return _Card(children: [
      SwitchListTile(
        title: const Text('Show caller pop-up'),
        subtitle: const Text('Customer, lead or deal name while a call rings or is dialled'),
        value: s.enabled,
        onChanged: (v) async {
          await setCallerIdEnabled(v);
          _refresh();
        },
      ),
      SwitchListTile(
        title: const Text('After-call screen'),
        subtitle: const Text('When a work call ends, open Hipersign to save the recording and add a follow-up - even if the app is closed'),
        value: s.afterCall,
        onChanged: s.enabled
            ? (v) async {
                await setAfterCallEnabled(v);
                _refresh();
              }
            : null,
      ),
      ListTile(
        leading: Icon(s.phone ? Icons.check_circle : Icons.phone_locked_outlined,
            color: s.phone ? HsColors.completed : HsColors.warning),
        title: const Text('Phone & call log access'),
        subtitle: Text(s.phone ? 'Allowed' : 'Needed to see who is calling'),
        trailing: s.phone
            ? null
            : TextButton(
                onPressed: () async {
                  final r = await requestCallerIdPermissions();
                  if (r != null && !r.phone) {
                    showSnack('Allow "Phone" and "Call logs" for Hipersign in phone settings.', error: true);
                    await openAppSettings();
                  }
                  _refresh();
                },
                child: const Text('Allow'),
              ),
      ),
      ListTile(
        leading: Icon(s.overlay ? Icons.check_circle : Icons.layers_outlined,
            color: s.overlay ? HsColors.completed : HsColors.warning),
        title: const Text('Display over other apps'),
        subtitle: Text(s.overlay ? 'Allowed - the card shows over the call screen' : 'Off - a notification is shown instead'),
        trailing: s.overlay ? null : TextButton(onPressed: openOverlaySettings, child: const Text('Allow')),
      ),
      ListTile(
        leading: const Icon(Icons.contacts_outlined),
        title: Text('${s.entries} numbers from ERPNext'),
        subtitle: const Text('Updated automatically every 30 minutes'),
        trailing: _syncing
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton(onPressed: _sync, child: const Text('Update now')),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Text(
          'Xiaomi / Redmi / POCO: also open phone Settings > Apps > Hipersign > Other permissions and allow '
          '"Display pop-up windows while running in the background", and turn on Autostart.',
          style: TextStyle(fontSize: 12.5, color: HsColors.textSecondary, height: 1.4),
        ),
      ),
    ]);
  }
}
