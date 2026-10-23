import 'models.dart';

int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

/// A file or voice note on a task, development work, trial / training, suggestion or concern.
class Attachment {
  Attachment({required this.id, required this.name, required this.kind, this.size = 0, this.by, this.byUser, this.at});

  final String id;
  final String name;
  final String kind; // audio | image | video | document
  final int size;
  final String? by;
  final String? byUser;
  final DateTime? at;

  String get ext => name.contains('.') ? name.split('.').last.toLowerCase() : 'bin';

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        id: j['id'].toString(),
        name: j['name']?.toString() ?? 'File',
        kind: j['kind']?.toString() ?? 'document',
        size: _int(j['size']),
        by: str(j['by']),
        byUser: str(j['by_user']),
        at: parseDate(j['at']),
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
  });

  final String user;
  final String name;
  final DateTime date;
  final List<ReportItem> items;
  final int done;
  final int notDone;
  final int callsMade;
  final int callsConnected;
  final int? callTarget;
  final int newConnected;
  final int meetingsAssigned;
  final int? meetingTarget;

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
        meetingTarget: (j['meeting_target'] as num?)?.toInt(),
      );
}
