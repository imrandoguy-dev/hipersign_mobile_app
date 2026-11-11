import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../models/models.dart';
import 'common.dart';
import 'contact_actions.dart';

/// Pastel card coloured by state: light blue = scheduled, yellow-orange = pending,
/// green = completed, violet = rescheduled. The status label is always shown too.
class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.activity, required this.onTap, this.stateOverride, this.onContact, this.showPeople = false});

  final Activity activity;
  final VoidCallback onTap;
  final ActivityState? stateOverride;
  final void Function(String channel)? onContact;
  final bool showPeople; // whose it is (team lists)

  IconData get _typeIcon => switch (activity.activityType) {
        'Meeting' => Icons.groups_2_outlined,
        'Trial' => Icons.school_outlined,
        _ => Icons.phone_callback_outlined,
      };

  @override
  Widget build(BuildContext context) {
    // Missed work stands out: open and its time has passed -> red "Overdue".
    final overdue = activity.isOpen && activity.start != null && activity.start!.isBefore(DateTime.now());
    final state = overdue ? ActivityState.overdue : (stateOverride ?? activity.state);
    final a = activity;
    final when = a.start == null
        ? 'No date set'
        : (overdue
            ? 'Overdue · was ${relativeDay(a.start!)}, ${fmtTime(a.start)}'
            : '${relativeDay(a.start!)} · ${fmtTime(a.start)} - ${fmtTime(a.end)}');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Semantics(
        label: '${a.activityType}, ${state.label}, ${a.title}, $when',
        child: Material(
          color: state.color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: overdue ? const BorderSide(color: HsColors.overdueEdge, width: 1.5) : BorderSide.none,
          ),
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
                      if (showPeople && a.people.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.person_outline, size: 14, color: HsColors.onPastel),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(a.people.map((p) => p.name).join(', '),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          ),
                        ]),
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
                      // What was noted when it was done (meeting notes / outcome).
                      if ((a.completionNotes ?? '').trim().isNotEmpty || (a.outcome ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(Icons.sticky_note_2_outlined, size: 14, color: HsColors.onPastel),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              [
                                if ((a.outcome ?? '').trim().isNotEmpty) a.outcome!.trim(),
                                if ((a.completionNotes ?? '').trim().isNotEmpty) a.completionNotes!.trim(),
                              ].join(' · '),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic),
                            ),
                          ),
                        ]),
                      ],
                    ]),
                  ),
                ),
                if (a.party != null) ...[
                  const SizedBox(width: 10),
                  ContactButtons(
                    phone: a.party!.primaryPhone,
                    party: a.party,
                    activityId: a.id,
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
