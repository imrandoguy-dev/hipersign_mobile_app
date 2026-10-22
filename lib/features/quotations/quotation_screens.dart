import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../../app/nav.dart';
import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/models.dart';
import '../../shared/models/sales.dart';
import '../../shared/widgets/common.dart';

String _money(double v) => NumberFormat('#,##0.##').format(v);

/// New quotation for a customer / lead / deal: items, quantities, prices, taxes.
class QuotationForm extends StatefulWidget {
  const QuotationForm({super.key, required this.party});
  final Party party;

  @override
  State<QuotationForm> createState() => _QuotationFormState();
}

class _QuotationFormState extends State<QuotationForm> {
  List<QuoteCompany> _companies = [];
  String? _company;
  String? _tax;
  final List<QuoteLine> _lines = [];
  int _validDays = 30;
  final _terms = TextEditingController();
  bool _loading = true;

  QuoteCompany? get _co {
    for (final c in _companies) {
      if (c.name == _company) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final (companies, def) = await context.read<SessionController>().repo.quoteOptions();
        if (!mounted) return;
        setState(() {
          _companies = companies;
          _company = def ?? (companies.isNotEmpty ? companies.first.name : null);
          _tax = _co?.defaultTax;
        });
      } on ApiException catch (e) {
        showSnack(e.message, error: true);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  void dispose() {
    _terms.dispose();
    super.dispose();
  }

  double get _total => _lines.fold(0, (a, l) => a + l.qty * l.rate);

  Future<void> _addItem() async {
    final line = await showModalBottomSheet<QuoteLine>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemPicker(company: _company),
    );
    if (line == null || !mounted) return;
    final edited = await _editLine(line);
    if (edited != null) setState(() => _lines.add(edited));
  }

  Future<QuoteLine?> _editLine(QuoteLine l) async {
    final qty = TextEditingController(text: _money(l.qty));
    final rate = TextEditingController(text: l.rate == 0 ? '' : _money(l.rate).replaceAll(',', ''));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.name),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Quantity${l.uom != null ? ' (${l.uom})' : ''}')),
          const SizedBox(height: 10),
          TextField(
            controller: rate,
            autofocus: l.rate == 0,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Price per unit${_co != null ? ' (${_co!.currency})' : ''}'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true) return null;
    final q = double.tryParse(qty.text.replaceAll(',', '').trim()) ?? 0;
    final r = double.tryParse(rate.text.replaceAll(',', '').trim()) ?? -1;
    if (q <= 0) {
      showSnack('Enter a quantity more than 0.', error: true);
      return null;
    }
    if (r < 0) {
      showSnack('Enter the price.', error: true);
      return null;
    }
    return QuoteLine(code: l.code, name: l.name, qty: q, rate: r, uom: l.uom, description: l.description);
  }

  Future<void> _save({required bool submit}) async {
    if (_company == null) return showMissing(context, 'Company not selected', 'Choose which company the quotation is from.');
    if (_lines.isEmpty) {
      return showMissing(context, 'No items', 'Add at least one item or service.', fixLabel: 'Add item', onFix: _addItem);
    }
    final repo = context.read<SessionController>().repo;
    final q = await runWrite(
      context,
      () => repo.createQuote({
        'doctype': widget.party.doctype,
        'name': widget.party.id,
        'company': _company,
        'taxes': _tax,
        'valid_days': _validDays,
        'terms': _terms.text.trim().isEmpty ? null : _terms.text.trim(),
        'submit': submit ? 1 : 0,
        'items': [for (final l in _lines) {'code': l.code, 'qty': l.qty, 'rate': l.rate}],
      }),
      success: submit ? 'Quotation saved and submitted' : 'Quotation saved as draft',
    );
    if (q == null || !mounted) return;
    bumpRefresh();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => QuotationScreen(id: q.id, party: widget.party)));
  }

  @override
  Widget build(BuildContext context) {
    final co = _co;
    return Scaffold(
      appBar: AppBar(title: Text('Quotation - ${widget.party.name}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
              if (_companies.length > 1)
                DropdownButtonFormField<String>(
                  initialValue: _company,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'From company'),
                  items: [for (final c in _companies) DropdownMenuItem(value: c.name, child: Text('${c.name} (${c.currency})'))],
                  onChanged: (v) => setState(() {
                    _company = v;
                    _tax = _co?.defaultTax;
                  }),
                ),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                FilledButton.tonalIcon(onPressed: _addItem, icon: const Icon(Icons.add), label: const Text('Add item')),
              ]),
              if (_lines.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Add the products or services to quote.', style: TextStyle(color: HsColors.textSecondary)),
                ),
              for (var i = 0; i < _lines.length; i++)
                Card(
                  elevation: 0,
                  color: HsColors.card,
                  margin: const EdgeInsets.only(top: 8),
                  child: ListTile(
                    title: Text(_lines[i].name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${_money(_lines[i].qty)} × ${_money(_lines[i].rate)} = ${_money(_lines[i].qty * _lines[i].rate)}'),
                    onTap: () async {
                      final e = await _editLine(_lines[i]);
                      if (e != null) setState(() => _lines[i] = e);
                    },
                    trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _lines.removeAt(i))),
                  ),
                ),
              if (_lines.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('Total before tax: ${co?.currency ?? ''} ${_money(_total)}',
                      textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              const SizedBox(height: 16),
              if (co != null && co.taxes.isNotEmpty)
                DropdownButtonFormField<String?>(
                  key: ValueKey('tax-$_company'),
                  initialValue: co.taxes.contains(_tax) ? _tax : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Taxes'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('No taxes')),
                    for (final t in co.taxes) DropdownMenuItem<String?>(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => setState(() => _tax = v),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _validDays,
                decoration: const InputDecoration(labelText: 'Valid for'),
                items: [for (final d in const [7, 15, 30, 45, 60, 90]) DropdownMenuItem(value: d, child: Text('$d days'))],
                onChanged: (v) => setState(() => _validDays = v ?? 30),
              ),
              const SizedBox(height: 12),
              TextField(controller: _terms, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Terms / notes (optional)', alignLabelWithHint: true)),
            ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _save(submit: false), child: const Text('Save draft'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(onPressed: () => _save(submit: true), child: const Text('Save & submit'))),
          ]),
        ),
      ),
    );
  }
}

class _ItemPicker extends StatefulWidget {
  const _ItemPicker({required this.company});
  final String? company;

  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  final _q = TextEditingController();
  List<QuoteLine> _items = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final items = await context.read<SessionController>().repo.quoteItems(_q.text.trim(), widget.company);
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _q,
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search items / services'),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), _search);
            },
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: ListView(children: [
            if (!_loading && _items.isEmpty) const EmptyState(icon: Icons.inventory_2_outlined, title: 'No items found'),
            for (final i in _items)
              ListTile(
                title: Text(i.name),
                subtitle: Text([i.code, if (i.description != null) i.description!].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Text(i.rate > 0 ? _money(i.rate) : '-', style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(context, i),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// A quotation: lines, totals, PDF, WhatsApp, submit.
class QuotationScreen extends StatefulWidget {
  const QuotationScreen({super.key, required this.id, this.party});
  final String id;
  final Party? party;

  @override
  State<QuotationScreen> createState() => _QuotationScreenState();
}

class _QuotationScreenState extends State<QuotationScreen> {
  Quote? _q;
  ApiException? _error;
  bool _pdfBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final q = await context.read<SessionController>().repo.quote(widget.id);
      if (mounted) setState(() => _q = q);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pdf() async {
    setState(() => _pdfBusy = true);
    try {
      final path = await context.read<SessionController>().repo.quotePdf(widget.id);
      final r = await OpenFilex.open(path);
      if (r.type != ResultType.done) showSnack('No app on this phone can open PDFs.', error: true);
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _whatsapp() async {
    final phones = widget.party?.phones.where((p) => p.valid && p.e164 != null).toList() ?? [];
    String? phone = phones.isNotEmpty ? phones.first.e164 : null;
    if (phones.length > 1) {
      phone = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Send to'),
          children: [for (final p in phones) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, p.e164), child: Text(p.e164!))],
        ),
      );
    }
    if (phone == null) {
      if (phones.isEmpty) showSnack('No WhatsApp number for this customer.', error: true);
      return;
    }
    if (!mounted) return;
    final repo = context.read<SessionController>().repo;
    await runWrite(context, () => repo.sendQuoteWhatsApp(widget.id, phone!).then((_) => true), success: 'Quotation sent on WhatsApp');
  }

  Future<void> _submit() async {
    final repo = context.read<SessionController>().repo;
    final q = await runWrite(context, () => repo.submitQuote(widget.id), success: 'Submitted');
    if (q != null && mounted) {
      bumpRefresh();
      setState(() => _q = q);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    final wa = context.read<SessionController>().profile?.can('whatsapp') ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(q?.id ?? 'Quotation')),
      body: q == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!.message))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: q.submitted ? HsColors.completed : HsColors.pending, borderRadius: BorderRadius.circular(18)),
                child: DefaultTextStyle(
                  style: const TextStyle(color: HsColors.onPastel),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Text(q.status, style: const TextStyle(fontWeight: FontWeight.w700)), const Spacer(), Text(q.company ?? '')]),
                    const SizedBox(height: 8),
                    Text(q.party, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(q.totalText, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    if (q.taxText != null && q.netText != null) Text('${q.netText} + tax ${q.taxText}'),
                    const SizedBox(height: 4),
                    Text([
                      if (q.date != null) DateFormat('d MMM yyyy').format(q.date!),
                      if (q.validTill != null) 'valid till ${DateFormat('d MMM').format(q.validTill!)}',
                      if (q.by != null) 'by ${q.by}',
                    ].join(' · ')),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              for (final l in q.items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.name),
                  subtitle: Text('${_money(l.qty)} ${l.uom ?? ''} × ${_money(l.rate)}'),
                  trailing: Text(l.amountText ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _pdfBusy ? null : _pdf,
                icon: _pdfBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Open PDF'),
              ),
              if (wa && widget.party != null) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: HsColors.whatsapp),
                  onPressed: _whatsapp,
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Send PDF on WhatsApp'),
                ),
              ],
              if (!q.submitted) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: _submit, icon: const Icon(Icons.check), label: const Text('Submit (final)')),
              ],
            ]),
    );
  }
}

/// Stage chip + journey card for the customer page.
class JourneyCard extends StatelessWidget {
  const JourneyCard({super.key, required this.journey});
  final Journey journey;

  static Color colorFor(String key, String state) {
    if (state == 'cancelled') return HsColors.cancelled;
    return switch (key) {
      'development' => HsColors.rescheduled,
      'training' || 'trial' => HsColors.active,
      'quotation' => HsColors.pending,
      'customer' => HsColors.completed,
      _ => HsColors.card,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = journey.stage;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: s == null ? HsColors.card : colorFor(s.key, s.state),
        borderRadius: BorderRadius.circular(18),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: HsColors.onPastel),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.flag_outlined, size: 18, color: HsColors.onPastel),
            const SizedBox(width: 6),
            const Text('Stage: ', style: TextStyle(fontWeight: FontWeight.w600)),
            Expanded(child: Text(s?.label ?? 'New', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ]),
          if (s?.detail != null) Padding(padding: const EdgeInsets.only(top: 2, left: 24), child: Text(s!.detail!)),
          if (journey.steps.length > 1) ...[
            const SizedBox(height: 10),
            for (final st in journey.steps)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(
                    switch (st.state) {
                      'done' => Icons.check_circle,
                      'active' => Icons.play_circle_fill,
                      'upcoming' => Icons.schedule,
                      'cancelled' => Icons.cancel_outlined,
                      _ => Icons.radio_button_unchecked,
                    },
                    size: 16,
                    color: HsColors.onPastel,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('${st.label}${st.detail != null ? ' - ${st.detail}' : ''}', style: const TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
          ],
        ]),
      ),
    );
  }
}
