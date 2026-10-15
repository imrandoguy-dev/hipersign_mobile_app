import 'package:flutter/material.dart';

/// Reminder times people can pick (minutes before the start).
const reminderChoices = [1440, 120, 60, 30, 15, 10, 5, 0];

String reminderLabel(int m) {
  if (m == 0) return 'At start time';
  if (m % 1440 == 0) return m == 1440 ? '1 day before' : '${m ~/ 1440} days before';
  if (m >= 60 && m % 60 == 0) return '${m ~/ 60} h before';
  return '$m min before';
}

/// [60, 15, 0] -> "1 h before, 15 min before, at start time"
String describeReminders(List<int> offsets) {
  final sorted = [...offsets]..sort((a, b) => b.compareTo(a));
  final text = sorted.map(reminderLabel).join(', ');
  return text.isEmpty ? 'None' : text[0] + text.substring(1).replaceAll('At start', 'at start');
}

/// Result of the picker: `useDefault` = follow my reminder setting.
class ReminderChoice {
  const ReminderChoice(this.offsets, {this.useDefault = false});
  final List<int> offsets;
  final bool useDefault;
}

/// Bottom sheet to choose one or more reminder times (up to 5).
Future<ReminderChoice?> pickReminders(
  BuildContext context, {
  required List<int> initial,
  bool allowDefault = false,
  bool initiallyDefault = false,
  String? defaultText,
}) {
  return showModalBottomSheet<ReminderChoice>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final selected = {...initial};
      var useDefault = initiallyDefault;
      return StatefulBuilder(builder: (ctx, setState) {
        final choices = {...reminderChoices, ...selected}.toList()..sort((a, b) => b.compareTo(a));
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Remind me', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Choose one or more (up to 5).'),
              if (allowDefault)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use my reminder setting'),
                  subtitle: defaultText == null ? null : Text(defaultText),
                  value: useDefault,
                  onChanged: (v) => setState(() => useDefault = v),
                ),
              const SizedBox(height: 8),
              Opacity(
                opacity: useDefault ? 0.4 : 1,
                child: IgnorePointer(
                  ignoring: useDefault,
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final m in choices)
                      FilterChip(
                        label: Text(reminderLabel(m)),
                        selected: selected.contains(m),
                        onSelected: (on) => setState(() {
                          if (on && selected.length >= 5) return;
                          on ? selected.add(m) : selected.remove(m);
                        }),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: !useDefault && selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                            ctx,
                            ReminderChoice((selected.toList()..sort((a, b) => b.compareTo(a))), useDefault: useDefault),
                          ),
                  child: const Text('Done'),
                ),
              ),
            ]),
          ),
        );
      });
    },
  );
}
