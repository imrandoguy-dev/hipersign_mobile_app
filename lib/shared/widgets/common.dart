import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_client.dart';

String fmtTime(DateTime? d) => d == null ? '--' : DateFormat.jm().format(d);
String fmtDay(DateTime? d) => d == null ? 'No date' : DateFormat('EEE, d MMM').format(d);
String fmtDayTime(DateTime? d) => d == null ? 'No date set' : DateFormat('EEE d MMM, h:mm a').format(d);

/// "Today", "Tomorrow", "Yesterday", else "Fri 16 Oct" (with the year when it isn't this year).
String relativeDay(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final days = DateTime(d.year, d.month, d.day).difference(DateTime(n.year, n.month, n.day)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days == -1) return 'Yesterday';
  return DateFormat(d.year == n.year ? 'EEE d MMM' : 'EEE d MMM yyyy').format(d);
}

String ago(DateTime? d) {
  if (d == null) return 'never';
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return DateFormat('d MMM, h:mm a').format(d);
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.state, {super.key, this.onPastel = true, this.text});

  final ActivityState state;
  final bool onPastel;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final bg = onPastel ? Colors.black.withValues(alpha: 0.10) : state.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(state.icon, size: 14, color: HsColors.onPastel),
        const SizedBox(width: 4),
        Text(text ?? state.label,
            style: const TextStyle(color: HsColors.onPastel, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// "Last synced" line plus an offline / error banner (FR-058, FR-060).
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key, this.syncedAt, this.error});

  final DateTime? syncedAt;
  final ApiException? error;

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text('Last synced ${ago(syncedAt)}',
            style: const TextStyle(color: HsColors.textSecondary, fontSize: 12)),
      );
    }
    final offline = error!.isNetwork;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: HsColors.warningBg, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(offline ? Icons.cloud_off : Icons.error_outline, size: 18, color: HsColors.warning),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            offline
                ? 'Offline - showing data from ${ago(syncedAt)}. Changes need a connection.'
                : error!.message,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 44, color: HsColors.textSecondary),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: HsColors.textSecondary)),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.count, this.color});

  final String title;
  final int? count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(children: [
        if (color != null) ...[
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
        ],
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text('$count', style: const TextStyle(color: HsColors.textSecondary)),
        ],
      ]),
    );
  }
}

/// Runs a server write with a blocking spinner and a clear success / failure message.
/// Success is only reported after the server accepted the change (FR-022, FR-058).
Future<T?> runWrite<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final result = await action();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (success != null) messenger?.showSnackBar(SnackBar(content: Text(success)));
    return result;
  } on ApiException catch (e) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    messenger?.showSnackBar(SnackBar(
      content: Text(e.message),
      backgroundColor: HsColors.danger,
      duration: const Duration(seconds: 5),
    ));
    return null;
  } catch (e) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    messenger?.showSnackBar(const SnackBar(content: Text('Something went wrong. Please try again.')));
    return null;
  }
}
