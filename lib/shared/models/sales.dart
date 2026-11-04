import 'models.dart';

double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

/// Where a customer stands (lead -> trial -> training -> quotation -> customer -> development).
class JourneyStep {
  JourneyStep({required this.key, required this.label, required this.state, this.detail, this.at});
  final String key;
  final String label;
  final String state; // done | active | upcoming | pending | cancelled
  final String? detail;
  final DateTime? at;

  factory JourneyStep.fromJson(Map<String, dynamic> j) => JourneyStep(
        key: j['key']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        state: j['state']?.toString() ?? 'done',
        detail: str(j['detail']),
        at: parseDate(j['at']),
      );
}

class Journey {
  Journey({this.stage, this.steps = const [], this.quotations = const [], this.invoices = const []});
  final JourneyStep? stage;
  final List<JourneyStep> steps;
  final List<QuoteSummary> quotations;
  final List<InvoiceSummary> invoices;

  static Journey? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    return Journey(
      stage: j['stage'] is Map ? JourneyStep.fromJson(Map<String, dynamic>.from(j['stage'] as Map)) : null,
      steps: ((j['steps'] as List?) ?? const []).map((e) => JourneyStep.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      quotations: ((j['quotations'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((q) => QuoteSummary(id: q['id'].toString(), status: q['status']?.toString() ?? '', totalText: q['total_text']?.toString() ?? '',
              date: DateTime.tryParse(q['date']?.toString() ?? '')))
          .toList(),
      invoices: ((j['invoices'] as List?) ?? const [])
          .map((e) => InvoiceSummary.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

class QuoteSummary {
  QuoteSummary({required this.id, required this.status, required this.totalText, this.date});
  final String id;
  final String status;
  final String totalText;
  final DateTime? date;
}

class QuoteLine {
  QuoteLine({required this.code, required this.name, this.qty = 1, this.rate = 0, this.uom, this.amountText, this.description});
  final String code;
  final String name;
  double qty;
  double rate;
  final String? uom;
  final String? amountText;
  final String? description;

  factory QuoteLine.fromJson(Map<String, dynamic> j) => QuoteLine(
        code: j['code'].toString(),
        name: j['name']?.toString() ?? j['code'].toString(),
        qty: _d(j['qty']) == 0 ? 1 : _d(j['qty']),
        rate: _d(j['rate']),
        uom: str(j['uom']),
        amountText: str(j['amount_text']),
        description: str(j['description']),
      );
}

class Quote {
  Quote({
    required this.id,
    required this.status,
    required this.submitted,
    required this.party,
    required this.totalText,
    this.netText,
    this.taxText,
    this.date,
    this.validTill,
    this.company,
    this.by,
    this.items = const [],
  });

  final String id;
  final String status;
  final bool submitted;
  final String party;
  final String totalText;
  final String? netText;
  final String? taxText;
  final DateTime? date;
  final DateTime? validTill;
  final String? company;
  final String? by;
  final List<QuoteLine> items;

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
        id: j['id'].toString(),
        status: j['status']?.toString() ?? '',
        submitted: j['submitted'] == true,
        party: j['party']?.toString() ?? '',
        totalText: j['total_text']?.toString() ?? '',
        netText: str(j['net_text']),
        taxText: str(j['tax_text']),
        date: DateTime.tryParse(j['date']?.toString() ?? ''),
        validTill: DateTime.tryParse(j['valid_till']?.toString() ?? ''),
        company: str(j['company']),
        by: str(j['by']),
        items: ((j['items'] as List?) ?? const []).map((e) => QuoteLine.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
}

class QuoteCompany {
  QuoteCompany({required this.name, required this.currency, this.taxes = const [], this.defaultTax, this.modes = const []});
  final String name;
  final String currency;
  final List<String> taxes;
  final String? defaultTax;
  final List<PayMode> modes; // payment modes with an account for this company (invoices)
}

class PayMode {
  const PayMode(this.name, this.type);
  final String name;
  final String type; // Cash | Bank | General | Phone
  bool get needsReference => type != 'Cash';

  static List<PayMode> listFrom(dynamic raw) => ((raw as List?) ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .map((m) => PayMode(m['name'].toString(), m['type']?.toString() ?? ''))
      .toList();
}

class InvoiceSummary {
  InvoiceSummary({required this.id, required this.status, required this.totalText, this.outstanding = 0, this.outstandingText, this.date});
  final String id;
  final String status;
  final String totalText;
  final double outstanding;
  final String? outstandingText;
  final DateTime? date;

  factory InvoiceSummary.fromJson(Map<String, dynamic> j) => InvoiceSummary(
        id: j['id'].toString(),
        status: j['status']?.toString() ?? '',
        totalText: j['total_text']?.toString() ?? '',
        outstanding: _d(j['outstanding']),
        outstandingText: str(j['outstanding_text']),
        date: DateTime.tryParse(j['date']?.toString() ?? ''),
      );
}

class InvoicePayment {
  InvoicePayment({required this.id, required this.amountText, this.mode, this.reference, this.date, this.by});
  final String id;
  final String amountText;
  final String? mode;
  final String? reference;
  final DateTime? date;
  final String? by;
}

class Invoice {
  Invoice({
    required this.id,
    required this.status,
    required this.submitted,
    required this.party,
    required this.totalText,
    this.total = 0,
    this.outstanding = 0,
    this.outstandingText,
    this.netText,
    this.taxText,
    this.date,
    this.dueDate,
    this.company,
    this.currency,
    this.by,
    this.items = const [],
    this.payments = const [],
    this.modes = const [],
  });

  final String id;
  final String status;
  final bool submitted;
  final String party;
  final String totalText;
  final double total;
  final double outstanding;
  final String? outstandingText;
  final String? netText;
  final String? taxText;
  final DateTime? date;
  final DateTime? dueDate;
  final String? company;
  final String? currency;
  final String? by;
  final List<QuoteLine> items;
  final List<InvoicePayment> payments;
  final List<PayMode> modes;

  bool get paid => submitted && outstanding <= 0;

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: j['id'].toString(),
        status: j['status']?.toString() ?? '',
        submitted: j['submitted'] == true,
        party: j['party']?.toString() ?? '',
        totalText: j['total_text']?.toString() ?? '',
        total: _d(j['total']),
        outstanding: _d(j['outstanding']),
        outstandingText: str(j['outstanding_text']),
        netText: str(j['net_text']),
        taxText: str(j['tax_text']),
        date: DateTime.tryParse(j['date']?.toString() ?? ''),
        dueDate: DateTime.tryParse(j['due_date']?.toString() ?? ''),
        company: str(j['company']),
        currency: str(j['currency']),
        by: str(j['by']),
        items: ((j['items'] as List?) ?? const []).map((e) => QuoteLine.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        payments: ((j['payments'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .map((m) => InvoicePayment(
                  id: m['id'].toString(),
                  amountText: m['amount_text']?.toString() ?? '',
                  mode: str(m['mode']),
                  reference: str(m['reference']),
                  date: DateTime.tryParse(m['date']?.toString() ?? ''),
                  by: str(m['by']),
                ))
            .toList(),
        modes: PayMode.listFrom(j['modes']),
      );
}
