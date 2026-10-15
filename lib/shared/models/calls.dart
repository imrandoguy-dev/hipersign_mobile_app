import 'models.dart';

/// One work call from the call log (Mobile Call Log).
class CallEntry {
  CallEntry({
    required this.id,
    required this.direction,
    required this.connected,
    required this.duration,
    required this.phone,
    this.at,
    this.callType,
    this.partyKind,
    this.partyDoctype,
    this.partyId,
    this.partyName,
    this.callerName,
    this.activityId,
    this.recordingId,
    this.recordingExt,
    this.attempts,
    this.firstAt,
  });

  final String id;
  final String direction; // Outgoing | Incoming | Missed
  final bool connected;
  final int duration; // seconds
  final String phone;
  final DateTime? at;
  final String? callType; // New | Follow-up
  final String? partyKind;
  final String? partyDoctype;
  final String? partyId;
  final String? partyName;
  final String? callerName;
  final String? activityId;
  final String? recordingId;
  final String? recordingExt;
  final int? attempts; // "not reached yet" list: calls made to this number so far
  final DateTime? firstAt;

  String get title => partyName ?? phone;

  Party? get party => partyId == null
      ? null
      : Party(kind: partyKind ?? '', doctype: partyDoctype ?? '', id: partyId!, name: partyName ?? partyId!);

  factory CallEntry.fromJson(Map<String, dynamic> j) {
    final p = j['party'] is Map ? Map<String, dynamic>.from(j['party'] as Map) : null;
    final r = j['recording'] is Map ? Map<String, dynamic>.from(j['recording'] as Map) : null;
    return CallEntry(
      id: j['id'].toString(),
      direction: j['direction']?.toString() ?? 'Outgoing',
      connected: j['connected'] == true,
      duration: (j['duration'] as num?)?.toInt() ?? 0,
      phone: j['phone']?.toString() ?? '',
      at: parseDate(j['at']),
      callType: str(j['call_type']),
      partyKind: str(p?['kind']),
      partyDoctype: str(p?['doctype']),
      partyId: str(p?['id']),
      partyName: str(p?['name']),
      callerName: str(j['caller_name']),
      activityId: str(j['activity_id']),
      recordingId: str(r?['id']),
      recordingExt: str(r?['ext']),
      attempts: (j['attempts'] as num?)?.toInt(),
      firstAt: parseDate(j['first_at']),
    );
  }
}

class CallsPage {
  CallsPage(this.items, this.nextCursor, this.today);
  final List<CallEntry> items;
  final String? nextCursor;
  final Map<String, int>? today; // total, connected, new_calls, followups, talk (seconds)

  factory CallsPage.fromJson(Map<String, dynamic> j) => CallsPage(
        ((j['items'] as List?) ?? const []).map((e) => CallEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        str(j['next_cursor']),
        j['today'] is Map
            ? Map<String, dynamic>.from(j['today'] as Map).map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0))
            : null,
      );
}
