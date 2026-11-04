import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// A sales invoice: lines, totals, what is still due, payments, PDF, WhatsApp, take a payment.
class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key, required this.id, this.party});
  final String id;
  final Party? party;

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  Invoice? _inv;
  ApiException? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final i = await context.read<SessionController>().repo.invoice(widget.id);
      if (mounted) setState(() => _inv = i);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pdf() async {
    setState(() => _busy = true);
    try {
      final path = await context.read<SessionController>().repo.invoicePdf(widget.id);
      final r = await OpenFilex.open(path);
      if (r.type != ResultType.done) showSnack('No app on this phone can open PDFs.', error: true);
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<PhoneInfo> get _phones => widget.party?.phones.where((p) => p.valid && p.e164 != null).toList() ?? [];

  Future<String?> _pickPhone({bool allowNone = false}) async {
    final phones = _phones;
    if (phones.isEmpty) return allowNone ? '' : null;
    if (phones.length == 1) return phones.first.e164;
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Send to'),
        children: [for (final p in phones) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, p.e164), child: Text(p.e164!))],
      ),
    );
  }

  /// The phone's own WhatsApp: opens the customer's chat with the PDF attached.
  Future<void> _phoneWhatsapp() async {
    final phone = await _pickPhone(allowNone: true);
    if (phone == null || !mounted) return;
    final inv = _inv!;
    setState(() => _busy = true);
    try {
      final path = await context.read<SessionController>().repo.invoicePdf(widget.id);
      await const MethodChannel('hipersign/phone').invokeMethod('shareFile', {
        'path': path,
        'mime': 'application/pdf',
        'whatsapp': true,
        'phone': phone,
        'text': 'Invoice ${inv.id} - ${inv.totalText}',
      });
      if (phone.isEmpty) showSnack('Pick the chat in WhatsApp to send the invoice.');
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } on PlatformException catch (e) {
      showSnack(e.code == 'NO_WHATSAPP' ? 'WhatsApp is not installed on this phone.' : (e.message ?? 'Could not open WhatsApp.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _companyWhatsapp() async {
    final phone = await _pickPhone();
    if (phone == null) {
      if (_phones.isEmpty) showSnack('No WhatsApp number for this customer.', error: true);
      return;
    }
    if (!mounted) return;
    final repo = context.read<SessionController>().repo;
    await runWrite(context, () => repo.sendInvoiceWhatsApp(widget.id, phone).then((_) => true), success: 'Invoice sent on WhatsApp');
  }

  Future<void> _submit() async {
    final repo = context.read<SessionController>().repo;
    final i = await runWrite(context, () => repo.submitInvoice(widget.id), success: 'Invoice submitted');
    if (i != null && mounted) {
      bumpRefresh();
      setState(() => _inv = i);
    }
  }

  Future<void> _takePayment() async {
    final inv = _inv!;
    if (inv.modes.isEmpty) {
      return showMissing(context, 'No payment mode',
          'In ERP, open Mode of Payment (Cash, UPI, Bank...) and set the account for ${inv.company ?? 'this company'}.');
    }
    final result = await showModalBottomSheet<(double, String, String?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PaymentSheet(invoice: inv),
    );
    if (result == null || !mounted) return;
    final repo = context.read<SessionController>().repo;
    final i = await runWrite(context, () => repo.recordPayment(widget.id, result.$1, result.$2, result.$3), success: 'Payment saved');
    if (i != null && mounted) {
      bumpRefresh();
      setState(() => _inv = i);
    }
  }

  Color _color(Invoice i) {
    if (!i.submitted) return HsColors.card;
    if (i.paid) return HsColors.completed;
    if (i.status == 'Overdue') return HsColors.cancelled;
    return HsColors.pending;
  }

  @override
  Widget build(BuildContext context) {
    final i = _inv;
    final wa = context.read<SessionController>().profile?.can('whatsapp') ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(i?.id ?? 'Invoice')),
      body: i == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!.message))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: _color(i), borderRadius: BorderRadius.circular(18)),
                  child: DefaultTextStyle(
                    style: const TextStyle(color: HsColors.onPastel),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(i.status, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Flexible(child: Text(i.company ?? '', overflow: TextOverflow.ellipsis)),
                      ]),
                      const SizedBox(height: 8),
                      Text(i.party, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(i.totalText, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      if (i.taxText != null && i.netText != null) Text('${i.netText} + tax ${i.taxText}'),
                      if (i.submitted && !i.paid && i.outstandingText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('Due: ${i.outstandingText}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                      const SizedBox(height: 4),
                      Text([
                        if (i.date != null) DateFormat('d MMM yyyy').format(i.date!),
                        if (i.by != null) 'by ${i.by}',
                      ].join(' · ')),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                for (final l in i.items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.name),
                    subtitle: Text('${_money(l.qty)} ${l.uom ?? ''} × ${_money(l.rate)}'),
                    trailing: Text(l.amountText ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                if (i.payments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Payments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  for (final p in i.payments)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.payments_outlined, color: HsColors.navy),
                      title: Text(p.amountText, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        if (p.mode != null) p.mode!,
                        if (p.date != null) DateFormat('d MMM yyyy').format(p.date!),
                        if (p.reference != null && !(p.reference!.contains(i.id))) p.reference!,
                        if (p.by != null) 'by ${p.by}',
                      ].join(' · ')),
                    ),
                ],
                const SizedBox(height: 16),
                if (i.submitted && !i.paid) ...[
                  FilledButton.icon(
                    onPressed: _takePayment,
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Take payment'),
                  ),
                  const SizedBox(height: 8),
                ],
                if (!i.submitted) ...[
                  FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.check), label: const Text('Submit invoice (final)')),
                  const SizedBox(height: 8),
                ],
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pdf,
                  icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Open PDF'),
                ),
                if (Platform.isAndroid) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: HsColors.whatsapp),
                    onPressed: _busy ? null : _phoneWhatsapp,
                    icon: const Icon(Icons.phone_android),
                    label: const Text('Send from my phone\'s WhatsApp'),
                  ),
                ],
                if (wa && widget.party != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _companyWhatsapp,
                    icon: const Icon(Icons.chat_outlined, color: HsColors.whatsapp),
                    label: const Text('Send from company WhatsApp'),
                  ),
                ],
              ]),
            ),
    );
  }
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.invoice});
  final Invoice invoice;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late final _amount = TextEditingController(text: _money(widget.invoice.outstanding).replaceAll(',', ''));
  final _ref = TextEditingController();
  late String _mode = widget.invoice.modes.first.name;

  PayMode get _m => widget.invoice.modes.firstWhere((m) => m.name == _mode);

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    super.dispose();
  }

  void _ok() {
    final a = double.tryParse(_amount.text.replaceAll(',', '').trim()) ?? 0;
    if (a <= 0) {
      showSnack('Enter the amount received.', error: true);
      return;
    }
    if (a > widget.invoice.outstanding + 0.01) {
      showSnack('Only ${widget.invoice.outstandingText} is due.', error: true);
      return;
    }
    Navigator.pop(context, (a, _mode, _ref.text.trim().isEmpty ? null : _ref.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Payment for ${inv.id}', style: Theme.of(context).textTheme.titleMedium),
        Text('Due: ${inv.outstandingText ?? ''}', style: const TextStyle(color: HsColors.textSecondary)),
        const SizedBox(height: 12),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Amount received${inv.currency != null ? ' (${inv.currency})' : ''}'),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _mode,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Paid by'),
          items: [for (final m in inv.modes) DropdownMenuItem(value: m.name, child: Text(m.name))],
          onChanged: (v) => setState(() => _mode = v ?? _mode),
        ),
        if (_m.needsReference) ...[
          const SizedBox(height: 10),
          TextField(controller: _ref, decoration: const InputDecoration(labelText: 'UTR / cheque / reference no. (optional)')),
        ],
        const SizedBox(height: 16),
        FilledButton(onPressed: _ok, child: const Text('Save payment')),
      ]),
    );
  }
}
