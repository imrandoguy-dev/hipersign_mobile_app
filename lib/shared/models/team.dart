import 'models.dart';

int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

/// A file or voice note on a task, development work, trial / training, suggestion or concern.
class Attachment {
  Attachment({required this.id, required this.name, required this.kind, this.size = 0, this.by, this.byUser, this.at, this.record, this.viaDoctype, this.viaName});

  final String id;
  final String name;
  final String kind; // audio | image | video | document
  final int size;
  final String? by;
  final String? byUser;
  final DateTime? at;
  final String? record; // which meeting / task it is on (customer page)
  // Opened from a customer's page: the customer it is about (lets the server check access that way).
  final String? viaDoctype;
  final String? viaName;

  Attachment via(String doctype, String party) => Attachment(
      id: id, name: name, kind: kind, size: size, by: by, byUser: byUser, at: at, record: record, viaDoctype: doctype, viaName: party);

  String get ext => name.contains('.') ? name.split('.').last.toLowerCase() : 'bin';

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        id: j['id'].toString(),
        name: j['name']?.toString() ?? 'File',
        kind: j['kind']?.toString() ?? 'document',
        size: _int(j['size']),
        by: str(j['by']),
        byUser: str(j['by_user']),
        at: parseDate(j['at']),
        record: str(j['record']),
      );
}

List<Attachment> attachmentsFrom(dynamic list) =>
    ((list as List?) ?? const []).map((e) => Attachment.fromJson(Map<String, dynamic>.from(e as Map))).toList();

/// An app bug / improvement / idea on the suggestions board.
class Suggestion {
  Suggestion({
    required this.id,
    required this.kind,
    required this.title,
    required this.status,
    this.details,
    this.reply,
    this.votes = 0,
    this.voted = false,
    this.by,
    this.isMine = false,
    this.at,
    this.canManage = false,
    this.files = const [],
  });

  final String id;
  final String kind;
  final String title;
  final String status;
  final String? details;
  final String? reply;
  final int votes;
  final bool voted;
  final String? by;
  final bool isMine;
  final DateTime? at;
  final bool canManage;
  final List<Attachment> files;

  factory Suggestion.fromJson(Map<String, dynamic> j) => Suggestion(
        id: j['id'].toString(),
        kind: j['kind']?.toString() ?? 'Improvement',
        title: j['title']?.toString() ?? '',
        status: j['status']?.toString() ?? 'New',
        details: str(j['details']),
        reply: str(j['reply']),
        votes: _int(j['votes']),
        voted: j['voted'] == true,
        by: str(j['by']),
        isMine: j['is_mine'] == true,
        at: parseDate(j['at']),
        canManage: j['can_manage'] == true,
        files: attachmentsFrom(j['files']),
      );
}

/// A problem raised privately (CEO only, or HR & managers).
class Concern {
  Concern({
    required this.id,
    required this.audience,
    required this.category,
    required this.subject,
    required this.status,
    this.details,
    this.response,
    this.respondedBy,
    this.by,
    this.isMine = false,
    this.canRespond = false,
    this.at,
    this.files = const [],
  });

  final String id;
  final String audience;
  final String category;
  final String subject;
  final String status;
  final String? details;
  final String? response;
  final String? respondedBy;
  final String? by;
  final bool isMine;
  final bool canRespond;
  final DateTime? at;
  final List<Attachment> files;

  factory Concern.fromJson(Map<String, dynamic> j) => Concern(
        id: j['id'].toString(),
        audience: j['audience']?.toString() ?? 'HR & Managers',
        category: j['category']?.toString() ?? 'Other',
        subject: j['subject']?.toString() ?? '',
        status: j['status']?.toString() ?? 'Open',
        details: str(j['details']),
        response: str(j['response']),
        respondedBy: str(j['responded_by']),
        by: str(j['by']),
        isMine: j['is_mine'] == true,
        canRespond: j['can_respond'] == true,
        at: parseDate(j['at']),
        files: attachmentsFrom(j['files']),
      );
}

/// Today's calls against the caller's target.
class TargetProgress {
  TargetProgress({
    required this.target,
    required this.made,
    required this.connected,
    required this.counted,
    required this.remaining,
    required this.reached,
    this.connectedOnly = false,
    this.newOnly = false,
    this.unit = 'calls',
    this.newConnected = 0,
    this.meetingTarget = 0,
    this.meetings = 0,
    this.meetingsRemaining = 0,
    this.lastCall,
    this.checkTimes = const [],
    this.idleMinutes = 0,
    this.workingDay = true,
    this.idle = false,
    this.idleFor,
    this.newNotReached = 0,
    this.newNotReachedToday = 0,
  });

  final int target;
  final int made;
  final int connected;
  final int counted;
  final int remaining;
  final bool reached;
  final bool connectedOnly;
  final bool newOnly;
  final String unit; // "new connected calls", "calls"...
  final int newConnected;
  final int meetingTarget;
  final int meetings;
  final int meetingsRemaining;
  final DateTime? lastCall;
  final List<String> checkTimes;
  final int idleMinutes;
  final bool workingDay;
  final bool idle; // no calls for the set time right now
  final String? idleFor; // "45 min"
  final int newNotReached; // new leads called that never connected (to call back)
  final int newNotReachedToday;

  static TargetProgress? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    return TargetProgress(
      target: _int(j['target']),
      made: _int(j['made']),
      connected: _int(j['connected']),
      counted: _int(j['counted']),
      remaining: _int(j['remaining']),
      reached: j['reached'] == true,
      connectedOnly: j['connected_only'] == true,
      newOnly: j['new_only'] == true,
      unit: j['unit']?.toString() ?? (j['connected_only'] == true ? 'connected calls' : 'calls'),
      newConnected: _int(j['new_connected']),
      meetingTarget: _int(j['meeting_target']),
      meetings: _int(j['meetings']),
      meetingsRemaining: _int(j['meetings_remaining']),
      lastCall: parseDate(j['last_call']),
      checkTimes: ((j['check_times'] as List?) ?? const []).map((e) => e.toString()).toList(),
      idleMinutes: _int(j['idle_minutes']),
      workingDay: j['working_day'] != false,
      idle: j['idle'] == true,
      newNotReached: _int(j['new_not_reached']),
      newNotReachedToday: _int(j['new_not_reached_today']),
      idleFor: str(j['idle_for']),
    );
  }
}

/// A caller's target settings (managers).
class CallerTarget {
  CallerTarget({
    required this.user,
    required this.name,
    required this.enabled,
    required this.dailyTarget,
    required this.checkTimes,
    required this.idleMinutes,
    required this.workStart,
    required this.workEnd,
    required this.connectedOnly,
    this.newOnly = false,
    this.meetingTarget = 0,
    this.progress,
  });

  final String user;
  final String name;
  final bool enabled;
  final int dailyTarget;
  final String checkTimes;
  final int idleMinutes;
  final String workStart;
  final String workEnd;
  final bool connectedOnly;
  final bool newOnly;
  final int meetingTarget;
  final TargetProgress? progress;

  factory CallerTarget.fromJson(Map<String, dynamic> j) => CallerTarget(
        user: j['user'].toString(),
        name: j['name']?.toString() ?? '',
        enabled: j['enabled'] == true,
        dailyTarget: _int(j['daily_target']),
        checkTimes: j['check_times']?.toString() ?? '',
        idleMinutes: _int(j['idle_minutes']),
        workStart: j['work_start']?.toString() ?? '09:30',
        workEnd: j['work_end']?.toString() ?? '18:00',
        connectedOnly: j['count_connected_only'] == true,
        newOnly: j['count_new_only'] == true,
        meetingTarget: _int(j['meeting_target']),
        progress: TargetProgress.fromJson(j['progress']),
      );
}

class ReportItem {
  ReportItem({required this.kind, required this.title, required this.result, this.party, this.at, this.done = false, this.open = false, this.refDoctype, this.refName});

  final String kind;
  final String title;
  final String result;
  final String? party;
  final String? at;
  final bool done;
  final bool open;
  final String? refDoctype;
  final String? refName;

  factory ReportItem.fromJson(Map<String, dynamic> j) => ReportItem(
        kind: j['kind']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        result: j['result']?.toString() ?? '',
        party: str(j['party']),
        at: str(j['at']),
        done: j['done'] == true,
        open: j['open'] == true,
        refDoctype: str(j['reference_doctype']),
        refName: str(j['reference_name']),
      );
}

/// One person's day: work due (done / not done) and calls.
class DailyReport {
  DailyReport({
    required this.user,
    required this.name,
    required this.date,
    required this.items,
    required this.done,
    required this.notDone,
    required this.callsMade,
    required this.callsConnected,
    this.callTarget,
    this.newConnected = 0,
    this.meetingsAssigned = 0,
    this.meetingTarget,
    this.newNotReached = 0,
    this.timeline,
  });

  final String user;
  final String name;
  final DateTime date;
  final List<ReportItem> items;
  final DayTimeline? timeline;
  final int done;
  final int notDone;
  final int callsMade;
  final int callsConnected;
  final int? callTarget;
  final int newConnected;
  final int meetingsAssigned;
  final int? meetingTarget;
  final int newNotReached; // new numbers called that day that never connected

  factory DailyReport.fromJson(Map<String, dynamic> j) => DailyReport(
        user: j['user']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        date: DateTime.parse(j['date'].toString()),
        items: ((j['items'] as List?) ?? const []).map((e) => ReportItem.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        done: _int(j['done']),
        notDone: _int(j['not_done']),
        callsMade: _int(j['calls_made']),
        callsConnected: _int(j['calls_connected']),
        callTarget: (j['call_target'] as num?)?.toInt(),
        newConnected: _int(j['new_connected']),
        meetingsAssigned: _int(j['meetings_assigned']),
        newNotReached: _int(j['new_not_reached']),
        meetingTarget: (j['meeting_target'] as num?)?.toInt(),
        timeline: j['timeline'] is Map ? DayTimeline.fromJson(Map<String, dynamic>.from(j['timeline'] as Map)) : null,
      );
}

/// A span on the day line (minutes from midnight).
class TimeSpan {
  TimeSpan(this.from, this.to, {this.kind = '', this.label = '', this.fromText = '', this.toText = '', this.done = false});
  final int from;
  final int to;
  final String kind; // meeting | followup | trial
  final String label;
  final String fromText;
  final String toText;
  final bool done;
  int get minutes => to - from;
}

class TimelineCall {
  TimelineCall(this.at, this.atText, this.connected, this.seconds, this.incoming, this.who);
  final int at;
  final String atText;
  final bool connected;
  final int seconds;
  final bool incoming;
  final String who;
}

/// The day as a line: work hours, what filled them, and the free gaps.
class DayTimeline {
  DayTimeline({
    required this.start,
    required this.end,
    required this.workStart,
    required this.workEnd,
    required this.until,
    this.blocks = const [],
    this.calls = const [],
    this.marks = const [],
    this.free = const [],
    this.busyMinutes = 0,
    this.freeMinutes = 0,
    this.longestFree = 0,
    this.minGap = 20,
  });

  final int start;
  final int end;
  final int workStart;
  final int workEnd;
  final int until; // nothing after this yet (today)
  final List<TimeSpan> blocks;
  final List<TimelineCall> calls;
  final List<(int, String, String)> marks; // (minute, time, what)
  final List<TimeSpan> free;
  final int busyMinutes;
  final int freeMinutes;
  final int longestFree;
  final int minGap;

  bool get empty => blocks.isEmpty && calls.isEmpty && marks.isEmpty;

  factory DayTimeline.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> l(String k) => ((j[k] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return DayTimeline(
      start: _int(j['start_min']),
      end: _int(j['end_min']),
      workStart: _int(j['work_start_min']),
      workEnd: _int(j['work_end_min']),
      until: _int(j['until_min']),
      blocks: [
        for (final b in l('blocks'))
          TimeSpan(_int(b['from_min']), _int(b['to_min']),
              kind: b['kind']?.toString() ?? '', label: b['label']?.toString() ?? '', fromText: b['from']?.toString() ?? '',
              toText: b['to']?.toString() ?? '', done: b['done'] == true),
      ],
      calls: [
        for (final c in l('calls'))
          TimelineCall(_int(c['at_min']), c['at']?.toString() ?? '', c['connected'] == true, _int(c['seconds']), c['incoming'] == true,
              c['who']?.toString() ?? ''),
      ],
      marks: [for (final m in l('marks')) (_int(m['at_min']), m['at']?.toString() ?? '', m['label']?.toString() ?? '')],
      free: [
        for (final f in l('free'))
          TimeSpan(_int(f['from_min']), _int(f['to_min']), fromText: f['from']?.toString() ?? '', toText: f['to']?.toString() ?? ''),
      ],
      busyMinutes: _int(j['busy_minutes']),
      freeMinutes: _int(j['free_minutes']),
      longestFree: _int(j['longest_free']),
      minGap: _int(j['min_gap']),
    );
  }
}
