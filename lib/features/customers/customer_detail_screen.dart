import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/activity_card.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/contact_actions.dart';
import '../activities/activity_detail_screen.dart';
import '../activities/activity_form.dart';
import '../trials/book_trial_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.doctype, required this.name, required this.title});

  final String doctype;
  final String name;
  final String title;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  Party? _party;
  List<Activity> _activities = [];
  Activity? _next;
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<SessionController>().repo.partyDetail(widget.doctype, widget.name);
      if (!mounted) return;
      setState(() {
        _party = Party.fromJson(d);
        _activities = ((d['activities'] as List?) ?? const [])
            .map((e) => Activity.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        _next = d['next_activity'] is Map ? Activity.fromJson(Map<String, dynamic>.from(d['next_activity'] as Map)) : null;
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
    final p = _party;
    final profile = context.read<SessionController>().profile!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: p == null
          ? (_loading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: EmptyState(
                    icon: Icons.error_outline,
                    title: 'Could not load this customer',
                    message: _error?.message,
                    action: FilledButton(onPressed: _load, child: const Text('Try again')),
                  ),
                ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
                if (_error != null) SyncBanner(error: _error),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: HsColors.card, borderRadius: BorderRadius.circular(20)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text([p.kind, if (p.subtitle != null) p.subtitle!, if (p.status != null) p.status!].join(' - '),
                        style: const TextStyle(color: HsColors.textSecondary)),
                    if (p.email != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: InkWell(
                          onTap: () => launchUrl(Uri(scheme: 'mailto', path: p.email)),
                          child: Row(children: [
                            const Icon(Icons.mail_outline, size: 18, color: HsColors.textSecondary),
                            const SizedBox(width: 8),
                            Text(p.email!),
                          ]),
                        ),
                      ),
                    if (p.phones.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('No phone number in ERP.', style: TextStyle(color: HsColors.textSecondary)),
                      ),
                    for (final ph in p.phones)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(ph.e164 ?? ph.raw, style: const TextStyle(fontSize: 15)),
                              Text(ph.valid ? (ph.label ?? 'Phone') : 'Invalid number - fix in ERP',
                                  style: TextStyle(fontSize: 12, color: ph.valid ? HsColors.textSecondary : HsColors.danger)),
                            ]),
                          ),
                          ContactButtons(phone: ph),
                        ]),
                      ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    if (profile.can('create_activity'))
                      ActionChip(
                        avatar: const Icon(Icons.phone_callback_outlined, size: 18),
                        label: const Text('Follow-up'),
                        onPressed: () async {
                          await openActivityForm(context, type: 'Follow-up', party: p);
                          _load();
                        },
                      ),
                    if (profile.can('create_activity'))
                      ActionChip(
                        avatar: const Icon(Icons.groups_2_outlined, size: 18),
                        label: const Text('Meeting'),
                        onPressed: () async {
                          await openActivityForm(context, type: 'Meeting', party: p);
                          _load();
                        },
                      ),
                    if (profile.can('trial_booking') && p.doctype != 'CRM Deal')
                      ActionChip(
                        avatar: const Icon(Icons.school_outlined, size: 18),
                        label: const Text('Book trial'),
                        onPressed: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => BookTrialScreen(party: p)));
                          _load();
                        },
                      ),
                  ]),
                ),
                if (_next != null) ...[
                  const SectionHeader('Next activity'),
                  ActivityCard(activity: _next!, onTap: () => _open(_next!)),
                ],
                SectionHeader('Your activities', count: _activities.length),
                if (_activities.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text('No activities with this customer yet.', style: TextStyle(color: HsColors.textSecondary)),
                  ),
                for (final a in _activities) ActivityCard(activity: a, onTap: () => _open(a)),
              ]),
            ),
    );
  }

  Future<void> _open(Activity a) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: a.id)));
    _load();
  }
}
