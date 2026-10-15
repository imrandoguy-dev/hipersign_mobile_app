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
    this.location,
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
  final PartyLocation? location; // only in the detail response

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
        location: j['location'] is Map ? PartyLocation.fromJson(Map<String, dynamic>.from(j['location'] as Map)) : null,
      );
}

/// Where a customer / lead / deal is: an address and/or its Google Maps business place.
class PartyLocation {
  PartyLocation({this.address, this.mapsUrl, this.placeId});

  final String? address;
  final String? mapsUrl; // the business on Google Maps (from the Google lookup)
  final String? placeId;

  factory PartyLocation.fromJson(Map<String, dynamic> j) => PartyLocation(
        address: str(j['address']),
        mapsUrl: str(j['maps_url']),
        placeId: str(j['place_id']),
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
    this.reminderOffsets,
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
  final List<int>? reminderOffsets; // own reminders (minutes before); null = my reminder setting

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
        reminderOffsets: j['reminder_offsets'] is List
            ? (j['reminder_offsets'] as List).map((e) => (e as num).toInt()).toList()
            : null,
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
    this.trial,
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
  final TrialPeriod? trial; // the multi-day trial this session belongs to

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
        trial: j['trial'] is Map ? TrialPeriod.fromJson(Map<String, dynamic>.from(j['trial'] as Map)) : null,
      );
}

/// A trial of N calendar days and its sessions, with the countdown.
class TrialPeriod {
  TrialPeriod({
    required this.series,
    required this.days,
    required this.startDate,
    required this.endDate,
    required this.phase,
    required this.dayNo,
    required this.daysLeft,
    required this.startsIn,
    required this.sessions,
    required this.sessionsDone,
    this.todayOff = false,
  });

  final String series; // id of the trial's first session
  final int days;
  final DateTime startDate;
  final DateTime endDate;
  final String phase; // upcoming | running | ended
  final int dayNo;
  final int daysLeft;
  final int startsIn;
  final List<TrialSession> sessions;
  final int sessionsDone;
  final bool todayOff; // Sunday / holiday: the trial pauses today

  bool get isMultiDay => days > 1 || sessions.length > 1;

  /// "Day 3 of 7 · 4 days left", "Starts tomorrow · 7-day trial", "Trial ended".
  String get countdown => switch (phase) {
        'upcoming' => '${startsIn <= 1 ? 'Starts tomorrow' : 'Starts in $startsIn days'} · $days-day trial',
        'ended' => 'Trial ended · $days days',
        _ when todayOff => 'Paused today (Sunday / holiday) · $daysLeft day${daysLeft == 1 ? '' : 's'} left',
        _ => daysLeft == 0
            ? 'Day $dayNo of $days · last day today'
            : 'Day $dayNo of $days · $daysLeft day${daysLeft == 1 ? '' : 's'} left',
      };

  factory TrialPeriod.fromJson(Map<String, dynamic> j) => TrialPeriod(
        series: j['series'].toString(),
        days: (j['days'] as num?)?.toInt() ?? 1,
        startDate: DateTime.parse(j['start_date'].toString()),
        endDate: DateTime.parse(j['end_date'].toString()),
        phase: j['phase']?.toString() ?? 'running',
        dayNo: (j['day_no'] as num?)?.toInt() ?? 0,
        daysLeft: (j['days_left'] as num?)?.toInt() ?? 0,
        startsIn: (j['starts_in'] as num?)?.toInt() ?? 0,
        sessions: ((j['sessions'] as List?) ?? const [])
            .map((e) => TrialSession.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        sessionsDone: (j['sessions_done'] as num?)?.toInt() ?? 0,
        todayOff: j['today_off'] == true,
      );
}

class TrialSession {
  TrialSession({required this.id, required this.status, this.sessionNo, this.start, this.end});

  final String id;
  final String status;
  final int? sessionNo;
  final DateTime? start;
  final DateTime? end;

  bool get isActive => status == 'Booked' || status == 'Rescheduled' || status == 'Pending Confirmation';

  factory TrialSession.fromJson(Map<String, dynamic> j) => TrialSession(
        id: j['id'].toString(),
        status: j['status']?.toString() ?? '',
        sessionNo: (j['session_no'] as num?)?.toInt(),
        start: parseDate(j['start']),
        end: parseDate(j['end']),
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

/// A business found on Google Maps for a phone number.
class GooglePlace {
  GooglePlace({required this.name, this.placeId, this.address, this.mapsUrl});

  final String name;
  final String? placeId;
  final String? address;
  final String? mapsUrl;

  factory GooglePlace.fromJson(Map<String, dynamic> j) => GooglePlace(
        name: j['name']?.toString() ?? '',
        placeId: str(j['place_id']),
        address: str(j['address']),
        mapsUrl: str(j['maps_url']),
      );
}

/// Who a dialed number belongs to: an ERP customer/lead, a Google business, or nobody yet.
class NumberLookup {
  NumberLookup({required this.phone, this.party, this.google, this.googleEnabled = false, this.googleError});

  final String phone;
  final Party? party;
  final GooglePlace? google;
  final bool googleEnabled;
  final String? googleError;

  /// A party the user may link calls to (another salesperson's private record is not).
  Party? get linkable => party != null && party!.kind != 'Hidden' ? party : null;

  factory NumberLookup.fromJson(Map<String, dynamic> j) => NumberLookup(
        phone: j['phone']?.toString() ?? '',
        party: j['party'] is Map ? Party.fromJson(Map<String, dynamic>.from(j['party'] as Map)) : null,
        google: j['google'] is Map ? GooglePlace.fromJson(Map<String, dynamic>.from(j['google'] as Map)) : null,
        googleEnabled: j['google_enabled'] == true,
        googleError: str(j['google_error']),
      );
}

/// A business shared to Hipersign from Google, resolved by the server.
class SharedPlace {
  SharedPlace({this.phone, this.party, this.google, this.error});

  final String? phone;
  final Party? party;
  final GooglePlace? google;
  final String? error;

  factory SharedPlace.fromJson(Map<String, dynamic> j) => SharedPlace(
        phone: str(j['phone']),
        party: j['party'] is Map ? Party.fromJson(Map<String, dynamic>.from(j['party'] as Map)) : null,
        google: j['google'] is Map ? GooglePlace.fromJson(Map<String, dynamic>.from(j['google'] as Map)) : null,
        error: str(j['error']),
      );
}

/// A note on a customer / lead / deal (Frappe CRM's FCRM Note).
class Note {
  Note({
    required this.id,
    required this.title,
    required this.text,
    this.ownerName,
    this.created,
    this.modified,
    this.canEdit = false,
    this.fromLead = false,
  });

  final String id;
  final String title;
  final String text;
  final String? ownerName;
  final DateTime? created;
  final DateTime? modified;
  final bool canEdit;
  final bool fromLead; // written on the lead this deal came from

  factory Note.fromJson(Map<String, dynamic> j, {String? partyDoctype}) => Note(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        text: j['text']?.toString() ?? '',
        ownerName: str(j['owner_name']),
        created: DateTime.tryParse(j['created']?.toString() ?? '')?.toLocal(),
        modified: DateTime.tryParse(j['modified']?.toString() ?? '')?.toLocal(),
        canEdit: j['can_edit'] == true,
        fromLead: partyDoctype == 'CRM Deal' && j['reference_doctype'] == 'CRM Lead',
      );
}


/// One field of the server-defined edit form for a customer / lead / deal.
class EditField {
  EditField({required this.key, required this.label, required this.type, this.value, this.options = const [], this.required = false, this.showIfKey, this.showIfValues = const []});

  final String key;
  final String label;
  final String type; // text | phone | email | select | multiline | number | date
  final String? value;
  final List<String> options;
  final bool required;
  final String? showIfKey; // only shown when that field has one of showIfValues
  final List<String> showIfValues;

  factory EditField.fromJson(Map<String, dynamic> j) {
    final show = j['show_if'] is Map ? Map<String, dynamic>.from(j['show_if'] as Map) : null;
    final v = j['value'];
    return EditField(
      key: j['key'].toString(),
      label: j['label']?.toString() ?? j['key'].toString(),
      type: j['type']?.toString() ?? 'text',
      value: v == null ? null : (v is double && v == v.roundToDouble() ? v.toInt().toString() : v.toString()),
      options: ((j['options'] as List?) ?? const []).map((e) => e.toString()).toList(),
      required: j['required'] == true,
      showIfKey: show?['key']?.toString(),
      showIfValues: ((show?['in'] as List?) ?? const []).map((e) => e.toString()).toList(),
    );
  }
}


/// Pending work first (in time order), then completed / cancelled (in time order).
List<Activity> openFirst(Iterable<Activity> items) {
  int byTime(Activity a, Activity b) =>
      (a.start ?? DateTime(9999)).compareTo(b.start ?? DateTime(9999));
  final open = items.where((a) => a.isOpen).toList()..sort(byTime);
  final closed = items.where((a) => !a.isOpen).toList()..sort(byTime);
  return [...open, ...closed];
}
