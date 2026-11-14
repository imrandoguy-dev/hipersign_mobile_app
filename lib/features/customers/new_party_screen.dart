import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import 'customer_detail_screen.dart';

/// New lead, deal or customer (from the + button). If the number is already in ERP, that
/// record is opened instead of making a duplicate.
class NewPartyScreen extends StatefulWidget {
  const NewPartyScreen({super.key, required this.kind});
  final String kind; // lead | deal | customer

  @override
  State<NewPartyScreen> createState() => _NewPartyScreenState();
}

class _NewPartyScreenState extends State<NewPartyScreen> {
  final _company = TextEditingController();
  final _person = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _saving = false;

  String get _label => switch (widget.kind) { 'deal' => 'deal', 'customer' => 'customer', _ => 'lead' };

  @override
  void dispose() {
    for (final c in [_company, _person, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_company.text.trim().isEmpty && _person.text.trim().isEmpty) {
      showSnack('Enter the company or the person\'s name.', error: true);
      return;
    }
    if (_phone.text.trim().isEmpty) {
      showSnack('Enter a phone number.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final (party, created) = await context.read<SessionController>().repo.createParty(
            widget.kind,
            company: _company.text.trim(),
            person: _person.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim(),
          );
      if (!mounted) return;
      bumpRefresh();
      showSnack(created ? 'New $_label saved' : 'This number is already in ERP: ${party.name}');
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(doctype: party.doctype, name: party.id, title: party.name)));
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('New $_label')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _company,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Company / business name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _person,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Contact person'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number')),
        const SizedBox(height: 12),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (optional)')),
        const SizedBox(height: 12),
        Text(
          widget.kind == 'deal'
              ? 'A deal is made the CRM way (lead → deal), with its contact and organisation.'
              : 'If this number is already in ERP, that record opens instead.',
          style: const TextStyle(fontSize: 12.5, color: HsColors.textSecondary),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save $_label')),
        ),
      ),
    );
  }
}
