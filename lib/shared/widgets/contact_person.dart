import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../models/models.dart';

/// Add another person (and number) at this customer's company.
Future<ContactPerson?> addContactPerson(BuildContext context, Party party) async {
  final name = TextEditingController();
  final phone = TextEditingController();
  final role = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('New contact at ${party.name}'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 8),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number')),
          const SizedBox(height: 8),
          TextField(controller: role, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Role (optional, e.g. Owner, Accountant)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return null;
  if (name.text.trim().isEmpty || phone.text.trim().isEmpty) {
    showSnack('Enter the name and phone number.', error: true);
    return null;
  }
  try {
    final c = await context.read<SessionController>().repo.addContactPerson(party.doctype, party.id,
        fullName: name.text.trim(), phone: phone.text.trim(), designation: role.text.trim().isEmpty ? null : role.text.trim());
    showSnack('Contact added');
    return c;
  } on ApiException catch (e) {
    showSnack(e.message, error: true);
    return null;
  }
}

/// Pick which person of the customer this is with (or add a new one).
/// Returns null when nothing was chosen; a ContactPerson with id null = the main contact.
Future<ContactPerson?> pickContactPerson(BuildContext context, Party party, {String? selectedId}) async {
  List<ContactPerson> people;
  try {
    people = await context.read<SessionController>().repo.partyContacts(party.doctype, party.id);
  } on ApiException catch (e) {
    showSnack(e.message, error: true);
    return null;
  }
  if (!context.mounted) return null;
  final picked = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Who at ${party.name}?', style: Theme.of(ctx).textTheme.titleMedium),
          ),
          for (final c in people)
            ListTile(
              leading: Icon((c.id ?? '') == (selectedId ?? '') ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: HsColors.navy),
              title: Text(c.name),
              subtitle: Text([if (c.designation != null) c.designation!, if (c.phone != null) c.phone!.e164 ?? c.phone!.raw].join(' · ')),
              onTap: () => Navigator.pop(ctx, c),
            ),
          if (people.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No contact persons yet.')),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1, color: HsColors.navy),
            title: const Text('Add a person'),
            onTap: () => Navigator.pop(ctx, 'add'),
          ),
        ]),
      ),
    ),
  );
  if (!context.mounted) return null;
  if (picked == 'add') return addContactPerson(context, party);
  return picked is ContactPerson ? picked : null;
}

/// Customer page: everyone at the company, with call / WhatsApp, and "Add person".
class ContactPersonsSection extends StatefulWidget {
  const ContactPersonsSection({super.key, required this.party, required this.buttons});
  final Party party;
  final Widget Function(PhoneInfo phone) buttons;

  @override
  State<ContactPersonsSection> createState() => _ContactPersonsSectionState();
}

class _ContactPersonsSectionState extends State<ContactPersonsSection> {
  List<ContactPerson>? _items;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final items = await context.read<SessionController>().repo.partyContacts(widget.party.doctype, widget.party.id);
      if (mounted) setState(() => _items = items);
    } on ApiException {
      if (mounted) setState(() => _items = const []);
    }
  }

  Future<void> _add() async {
    final c = await addContactPerson(context, widget.party);
    if (c != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('Contact persons${items == null ? '' : ' (${items.length})'}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          TextButton.icon(onPressed: _add, icon: const Icon(Icons.person_add_alt_1), label: const Text('Add person')),
        ]),
        if (items == null)
          const LinearProgressIndicator(minHeight: 2)
        else
          for (final c in items)
            Card(
              elevation: 0,
              color: HsColors.card,
              margin: const EdgeInsets.only(top: 6),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text([if (c.designation != null) c.designation!, if (c.phone != null) c.phone!.e164 ?? c.phone!.raw].join(' · '),
                          style: const TextStyle(fontSize: 12.5, color: HsColors.textSecondary)),
                    ]),
                  ),
                  if (c.phone != null) widget.buttons(c.phone!),
                ]),
              ),
            ),
      ]),
    );
  }
}
