import '../../app/theme.dart';

DateTime? parseDate(dynamic v) {
  if (v == null || v == '') return null;
  return DateTime.tryParse(v.toString())?.toLocal();
}

String? str(dynamic v) => v == null || v == '' ? null : v.toString();

class PhoneInfo {
  PhoneInfo({required this.raw, this.e164, required this.valid, this.label, this.telUrl, this.whatsappUrl});

  final String raw;
  final String? e164;
  final bool valid;
  final String? label;
  final String? telUrl;
  final String? whatsappUrl;

  factory PhoneInfo.fromJson(Map<String, dynamic> j) => PhoneInfo(
        raw: j['raw']?.toString() ?? '',
        e164: str(j['e164']),
        valid: j['valid'] == true,
        label: str(j['label']),
        telUrl: str(j['tel_url']),
        whatsappUrl: str(j['whatsapp_url']),
      );

  Map<String, dynamic> toJson() => {
        'raw': raw,
        'e164': e164,
        'valid': valid,
        'label': label,
        'tel_url': telUrl,
        'whatsapp_url': whatsappUrl,
      };
}

class Party {
  Party({
    required this.kind,
    required this.doctype,
    required this.id,
    required this.name,
    this.subtitle,
    this.email,
    this.status,
    this.phones = const [],
    this.primaryPhone,
  });

  final String kind; // Customer | Lead | Deal
  final String doctype; // Customer | CRM Lead | CRM Deal
  final String id;
  final String name;
  final String? subtitle;
  final String? email;
  final String? status;
  final List<PhoneInfo> phones;
  final PhoneInfo? primaryPhone;

  factory Party.fromJson(Map<String, dynamic> j) => Party(
        kind: j['kind']?.toString() ?? '',
        doctype: j['doctype']?.toString() ?? '',
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        subtitle: str(j['subtitle']),
        email: str(j['email']),
        status: str(j['status']),
        phones: ((j['phones'] as List?) ?? const [])
            .map((e) => PhoneInfo.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        primaryPhone: j['primary_phone'] is Map
            ? PhoneInfo.fromJson(Map<String, dynamic>.from(j['primary_phone'] as Map))
            : null,
      );
}

class HistoryEntry {
  HistoryEntry({required this.eventType, this.actorName, this.at, this.reason, this.oldStart, this.newStart, this.oldStatus, this.newStatus, this.source});

  final String eventType;
  final String? actorName;
  final DateTime? at;
  final String? reason;
  final DateTime? oldStart;
  final DateTime? newStart;
  final String? oldStatus;
  final String? newStatus;
  final String? source;

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        eventType: j['event_type']?.toString() ?? '',
        actorName: str(j['actor_name']) ?? str(j['actor']),
        at: parseDate(j['event_datetime']),
        reason: str(j['reason']),
        oldStart: parseDate(j['old_start_datetime']),
        newStart: parseDate(j['new_start_datetime']),
        oldStatus: str(j['old_status']),
        newStatus: str(j['new_status']),
        source: str(j['source']),
      );
}

class Activity {
  Activity({
    required this.id,
    required this.title,
    required this.activityType,
    required this.status,
    required this.state,
    required this.priority,
    this.start,
    this.end,
    this.isOverdue = false,
    this.description,
    this.location,
    this.visitType,
    this.meetingLink,
    this.rescheduleCount = 0,
    this.outcome,
    this.completionNotes,
    this.trialBooking,
    this.party,
    this.history = const [],
  });

  final String id;
  final String title;
  final String activityType; // Follow-up | Meeting | Trial
  final String status; // Pending | In Progress | Completed | Rescheduled | Cancelled
  final ActivityState state;
  final String priority;
  final DateTime? start;
  final DateTime? end;
  final bool isOverdue;
  final String? description;
  final String? location;
  final String? visitType;
  final String? meetingLink;
  final int rescheduleCount;
  final String? outcome;
  final String? completionNotes;
  final String? trialBooking;
  final Party? party;
  final List<HistoryEntry> history;

  bool get isOpen => status == 'Pending' || status == 'In Progress' || status == 'Rescheduled';

  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
        id: j['id'].toString(),
        title: j['title']?.toString() ?? '(untitled)',
        activityType: j['activity_type']?.toString() ?? 'Follow-up',
        status: j['status']?.toString() ?? 'Pending',
        state: ActivityStateStyle.parse(j['display_state']?.toString()),
        priority: j['priority']?.toString() ?? 'Medium',
        start: parseDate(j['start']),
        end: parseDate(j['end']),
        isOverdue: j['is_overdue'] == true,
        description: str(j['description']),
        location: str(j['location']),
        visitType: str(j['visit_type']),
        meetingLink: str(j['meeting_link']),
        rescheduleCount: (j['reschedule_count'] as num?)?.toInt() ?? 0,
        outcome: str(j['outcome']),
        completionNotes: str(j['completion_notes']),
        trialBooking: str(j['trial_booking']),
        party: j['party'] is Map ? Party.fromJson(Map<String, dynamic>.from(j['party'] as Map)) : null,
        history: ((j['history'] as List?) ?? const [])
            .map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class TrainerSlot {
  TrainerSlot({required this.id, required this.trainer, required this.trainerName, required this.start, required this.end, this.slotType, this.location, this.meetingLink});

  final String id;
  final String trainer;
  final String trainerName;
  final DateTime start;
  final DateTime end;
  final String? slotType;
  final String? location;
  final String? meetingLink;

  factory TrainerSlot.fromJson(Map<String, dynamic> j) => TrainerSlot(
        id: j['id'].toString(),
        trainer: j['trainer']?.toString() ?? '',
        trainerName: j['trainer_name']?.toString() ?? '',
        start: parseDate(j['start'])!,
        end: parseDate(j['end'])!,
        slotType: str(j['slot_type']),
        location: str(j['location']),
        meetingLink: str(j['meeting_link']),
      );
}

class Booking {
  Booking({
    required this.id,
    required this.status,
    required this.bookingType,
    required this.partyName,
    this.party,
    this.trainerName,
    this.start,
    this.end,
    this.activityId,
    this.notes,
    this.cancellationReason,
    this.completionNotes,
  });

  final String id;
  final String status;
  final String bookingType;
  final String partyName;
  final Party? party;
  final String? trainerName;
  final DateTime? start;
  final DateTime? end;
  final String? activityId;
  final String? notes;
  final String? cancellationReason;
  final String? completionNotes;

  bool get isActive => status == 'Booked' || status == 'Rescheduled' || status == 'Pending Confirmation';

  ActivityState get state => switch (status) {
        'Completed' => ActivityState.completed,
        'Cancelled' => ActivityState.cancelled,
        'Rescheduled' => ActivityState.rescheduled,
        _ => (start != null && start!.isBefore(DateTime.now())) ? ActivityState.pending : ActivityState.active,
      };

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        id: j['id'].toString(),
        status: j['status']?.toString() ?? '',
        bookingType: j['booking_type']?.toString() ?? '',
        partyName: j['party_name']?.toString() ?? '',
        party: j['party'] is Map ? Party.fromJson(Map<String, dynamic>.from(j['party'] as Map)) : null,
        trainerName: str(j['trainer_name']),
        start: parseDate(j['start']),
        end: parseDate(j['end']),
        activityId: str(j['activity_id']),
        notes: str(j['notes']),
        cancellationReason: str(j['cancellation_reason']),
        completionNotes: str(j['completion_notes']),
      );
}

class Profile {
  Profile({required this.user, required this.fullName, required this.roles, required this.capabilities, required this.workspaces, this.timezone});

  final String user;
  final String fullName;
  final List<String> roles;
  final Map<String, bool> capabilities;
  final List<String> workspaces;
  final String? timezone;

  bool can(String cap) => capabilities[cap] == true;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        user: j['user'].toString(),
        fullName: j['full_name']?.toString() ?? j['user'].toString(),
        roles: ((j['roles'] as List?) ?? const []).map((e) => e.toString()).toList(),
        capabilities: Map<String, dynamic>.from((j['capabilities'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k, v == true)),
        workspaces: ((j['workspaces'] as List?) ?? const []).map((e) => e.toString()).toList(),
        timezone: str(j['timezone']),
      );

  Map<String, dynamic> toJson() => {
        'user': user,
        'full_name': fullName,
        'roles': roles,
        'capabilities': capabilities,
        'workspaces': workspaces,
        'timezone': timezone,
      };

  /// Fingerprint used to drop cached data when the admin changes this user's access.
  String get accessKey => '${(roles.toList()..sort()).join(',')}|${(capabilities.entries.where((e) => e.value).map((e) => e.key).toList()..sort()).join(',')}';
}

class PageResult<T> {
  PageResult(this.items, this.nextCursor);
  final List<T> items;
  final String? nextCursor;
}

class AppNotice {
  AppNotice({required this.id, required this.title, this.body, this.route, this.at, required this.status, this.problem});

  final String id;
  final String title;
  final String? body;
  final String? route;
  final DateTime? at;
  final String status;
  final String? problem;

  factory AppNotice.fromJson(Map<String, dynamic> j) => AppNotice(
        id: j['id'].toString(),
        title: j['title']?.toString() ?? '',
        body: str(j['body']),
        route: str(j['route']),
        at: parseDate(j['at']),
        status: j['status']?.toString() ?? '',
        problem: str(j['delivery_problem']),
      );
}

class CallRecording {
  CallRecording({
    required this.id,
    required this.partyDoctype,
    required this.party,
    required this.partyName,
    this.phone,
    this.startedAt,
    this.durationSeconds = 0,
    this.recordedBy,
    this.recordedByName,
    this.activity,
    this.size = 0,
    this.ext,
  });

  final String id;
  final String partyDoctype;
  final String party;
  final String partyName;
  final String? phone;
  final DateTime? startedAt;
  final int durationSeconds;
  final String? recordedBy;
  final String? recordedByName;
  final String? activity;
  final int size;
  final String? ext;

  factory CallRecording.fromJson(Map<String, dynamic> j) => CallRecording(
        id: j['id']?.toString() ?? '',
        partyDoctype: j['party_doctype']?.toString() ?? '',
        party: j['party']?.toString() ?? '',
        partyName: j['party_name']?.toString() ?? '',
        phone: str(j['phone']),
        startedAt: DateTime.tryParse(j['started_at']?.toString() ?? '')?.toLocal(),
        durationSeconds: (j['duration_seconds'] as num?)?.toInt() ?? 0,
        recordedBy: str(j['recorded_by']),
        recordedByName: str(j['recorded_by_name']),
        activity: str(j['activity']),
        size: (j['size'] as num?)?.toInt() ?? 0,
        ext: str(j['ext']),
      );
}

String fmtDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (m >= 60) return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return '$m:${s.toString().padLeft(2, '0')}';
}
