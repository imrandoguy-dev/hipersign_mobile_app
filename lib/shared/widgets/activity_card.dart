import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../models/models.dart';
import 'common.dart';
import 'contact_actions.dart';

/// Pastel card coloured by state: light blue = scheduled, yellow-orange = pending,
/// green = completed, violet = rescheduled. The status label is always shown too.
class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.activity, required this.onTap, this.stateOverride, this.onContact});

  final Activity activity;
  final VoidCallback onTap;
  final ActivityState? stateOverride;
  final void Function(String channel)? onContact;

  IconData get _typeIcon => switch (activity.activityType) {
        'Meeting' => Icons.groups_2_outlined,
        'Trial' => Icons.school_outlined,
        _ => Icons.phone_callback_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final state = stateOverride ?? activity.state;
    final a = activity;
    final when = a.start == null
        ? 'No date set'
        : (a.isOverdue ? 'Overdue - ${fmtDayTime(a.start)}' : '${fmtTime(a.start)} - ${fmtTime(a.end)}');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Semantics(
        label: '${a.activityType}, ${state.label}, ${a.title}, $when',
        child: Material(
          color: state.color,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                  child: DefaultTextStyle(
                    style: const TextStyle(color: HsColors.onPastel),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(_typeIcon, size: 16, color: HsColors.onPastel),
                        const SizedBox(width: 6),
                        Text(a.activityType, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        StatusChip(state),
                      ]),
                      const SizedBox(height: 8),
                      Text(a.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      if (a.party != null) ...[
                        const SizedBox(height: 2),
                        Text(a.party!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                      ],
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.access_time, size: 14, color: HsColors.onPastel),
                        const SizedBox(width: 4),
                        Flexible(child: Text(when, style: const TextStyle(fontSize: 12.5))),
                        if (a.priority == 'High') ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.priority_high, size: 14, color: Color(0xFF8B1E1E)),
                          const Text('High', style: TextStyle(fontSize: 12, color: Color(0xFF8B1E1E))),
                        ],
                      ]),
                    ]),
                  ),
                ),
                if (a.party != null) ...[
                  const SizedBox(width: 10),
                  ContactButtons(
                    phone: a.party!.primaryPhone,
                    dark: true,
                    onCall: onContact == null ? null : () => onContact!('Call'),
                    onWhatsApp: onContact == null ? null : () => onContact!('WhatsApp'),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
