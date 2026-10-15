import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/contact_actions.dart';
import 'book_trial_screen.dart';
import 'trial_detail_screen.dart';
import 'trial_widgets.dart';

class TrialsScreen extends StatefulWidget {
  const TrialsScreen({super.key});

  @override
  State<TrialsScreen> createState() => _TrialsScreenState();
}

class _TrialsScreenState extends State<TrialsScreen> {
  String _status = 'Active';
  List<Booking> _items = [];
  bool _loading = false;
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
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final repo = context.read<SessionController>().repo;
    final cached = repo.cachedBookings(_status);
    setState(() {
      if (cached != null) {
        _items = cached;
        _syncedAt = repo.cached('trials:$_status')?.syncedAt;
      }
      _loading = true;
    });
    try {
      final list = await repo.bookings(_status);
      if (!mounted) return;
      setState(() {
        _items = list;
        _syncedAt = DateTime.now();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Trials & training')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'book-trial',
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const BookTrialScreen()));
          _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Book trial'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.only(bottom: 100), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(spacing: 8, children: [
              for (final s in const ['Active', 'Completed', 'Cancelled'])
                ChoiceChip(
                  label: Text(s),
                  selected: _status == s,
                  onSelected: (_) {
                    setState(() {
                      _status = s;
                      _items = [];
                    });
                    _load();
                  },
                ),
            ]),
          ),
          SyncBanner(syncedAt: _syncedAt, error: _error),
          if (_loading && _items.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          if (!_loading && _items.isEmpty)
            EmptyState(icon: Icons.school_outlined, title: 'No ${_status.toLowerCase()} bookings'),
          for (final b in _items) BookingCard(booking: b, onChanged: _load),
        ]),
      ),
    );
  }
}

class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.booking, this.onChanged});

  final Booking booking;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final state = b.state;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: state.color,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => TrialDetailScreen(bookingId: b.id)));
            onChanged?.call();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(children: [
              Expanded(
                child: DefaultTextStyle(
                  style: const TextStyle(color: HsColors.onPastel),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.school_outlined, size: 16, color: HsColors.onPastel),
                      const SizedBox(width: 6),
                      Text(b.bookingType, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      StatusChip(state, text: b.status),
                    ]),
                    const SizedBox(height: 8),
                    Text(b.partyName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                        '${(b.trial?.sessions.length ?? 1) > 1 ? 'Next: ' : ''}'
                        '${relativeDay(b.start ?? DateTime.now())}, ${fmtTime(b.start)} - with ${b.trainerName ?? 'trainer'}',
                        style: const TextStyle(fontSize: 13)),
                    if (b.trial != null && b.trial!.isMultiDay) ...[
                      const SizedBox(height: 6),
                      TrialCountdown(trial: b.trial!, compact: true),
                    ],
                    if (b.trial != null && b.trial!.sessions.where((s) => s.status != 'Cancelled').length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Training days: ${trainingDays(b.trial!.sessions)}'
                          '${b.trial!.sessionsDone > 0 ? ' · ${b.trial!.sessionsDone} done' : ''}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                  ]),
                ),
              ),
              if (b.party != null) ...[
                const SizedBox(width: 10),
                ContactButtons(phone: b.party!.primaryPhone, party: b.party, dark: true),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
