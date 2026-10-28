import 'models.dart';

class DevNote {
  DevNote(this.text, this.by, this.at);
  final String text;
  final String? by;
  final DateTime? at;
}

/// A piece of development work given to a developer, with a deadline.
class DevTask {
  DevTask({
    required this.id,
    this.kind = 'dev',
    this.team,
    this.attachments = 0,
    this.created,
    required this.title,
    required this.status,
    required this.priority,
    required this.developer,
    required this.developerName,
    this.description,
    this.assignedBy,
    this.assignedByName,
    this.deadline,
    this.late = false,
    this.lateText,
    this.reminders = const [],
    this.ownReminders = false,
    this.project,
    this.completedOn,
    this.deadlineChanges = 0,
    this.canEdit = false,
    this.isMine = false,
    this.notes = const [],
  });

  final String id;
  final String kind; // dev | team
  final String? team; // Accounts, Marketing... (team tasks)
  final int attachments;
  final DateTime? created;
  final String title;
  final String status; // Open | In Progress | In Review | Done | Cancelled
  final String priority;
  final String developer;
  final String developerName;
  final String? description;
  final String? assignedBy;
  final String? assignedByName;
  final DateTime? deadline;
  final bool late;
  final String? lateText;
  final List<int> reminders;
  final bool ownReminders;
  final String? project;
  final DateTime? completedOn;
  final int deadlineChanges;
  final bool canEdit;
  final bool isMine;
  final List<DevNote> notes;

  bool get isOpen => status == 'Open' || status == 'In Progress' || status == 'In Review';

  factory DevTask.fromJson(Map<String, dynamic> j) => DevTask(
        id: j['id'].toString(),
        kind: j['kind']?.toString() ?? 'dev',
        team: str(j['team']),
        attachments: (j['attachments'] as num?)?.toInt() ?? 0,
        created: parseDate(j['created']),
        title: j['title']?.toString() ?? '',
        status: j['status']?.toString() ?? 'Open',
        priority: j['priority']?.toString() ?? 'Medium',
        developer: j['developer']?.toString() ?? '',
        developerName: j['developer_name']?.toString() ?? j['developer']?.toString() ?? '',
        description: str(j['description']),
        assignedBy: str(j['assigned_by']),
        assignedByName: str(j['assigned_by_name']),
        deadline: parseDate(j['deadline']),
        late: j['late'] == true,
        lateText: str(j['late_text']),
        reminders: ((j['reminders'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        ownReminders: j['own_reminders'] == true,
        project: str(j['project']),
        completedOn: parseDate(j['completed_on']),
        deadlineChanges: (j['deadline_changes'] as num?)?.toInt() ?? 0,
        canEdit: j['can_edit'] == true,
        isMine: j['is_mine'] == true,
        notes: ((j['notes'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .map((n) => DevNote(n['text']?.toString() ?? '', str(n['by']), parseDate(n['at'])))
            .toList(),
      );
}

class DevPage {
  DevPage(this.items, this.nextCursor, this.open, this.late, {this.teams = const []});
  final List<DevTask> items;
  final String? nextCursor;
  final int open;
  final int late;
  final List<String> teams;
}

/// Is [t] on the calendar on [day]? Open work: every day from when it was given until its
/// deadline. Finished work: its deadline day.
bool taskOnDay(DevTask t, DateTime day) {
  final d = t.deadline;
  if (d == null) return false;
  DateTime only(DateTime x) => DateTime(x.year, x.month, x.day);
  final dl = only(d), x = only(day);
  if (!t.isOpen) return x == dl;
  final from = t.created != null ? only(t.created!) : dl;
  return !x.isBefore(from) && !x.isAfter(dl);
}
