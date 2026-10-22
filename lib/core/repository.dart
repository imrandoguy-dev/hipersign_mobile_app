import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';

import '../shared/models/calls.dart';
import '../shared/models/development.dart';
import '../shared/models/team.dart';
import '../shared/models/models.dart';
import '../shared/models/whatsapp.dart';
import 'api/api_client.dart';
import 'cache/cache_store.dart';

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Result of a cached read: [data] may come from cache while [error] says why
/// the network refresh failed (offline banner, last-synced time).
class Loaded<T> {
  Loaded(this.data, this.syncedAt, {this.error, this.fromCache = false});
  final T data;
  final DateTime? syncedAt;
  final ApiException? error;
  final bool fromCache;
}

class CalendarData {
  CalendarData({required this.items, required this.overdue, required this.unscheduled});
  final List<Activity> items;
  final List<Activity> overdue;
  final List<Activity> unscheduled;

  factory CalendarData.fromJson(Map<String, dynamic> j) {
    List<Activity> list(String k) =>
        ((j[k] as List?) ?? const []).map((e) => Activity.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    return CalendarData(items: list('items'), overdue: list('overdue'), unscheduled: list('unscheduled'));
  }
}

/// All server calls used by the screens, with read-through caching.
class Repository {
  Repository(this.api, this.cache);

  final ApiClient api;
  final CacheStore cache;

  /// Cached value for [key], or null.
  CachedEntry? cached(String key) => cache.read(key);

  /// Fetch from the server and cache the raw JSON on success.
  Future<dynamic> fetch(String key, String method, Map<String, dynamic> params) async {
    final data = await api.get(method, params);
    await cache.write(key, data);
    return data;
  }

  // ------------------------------------------------------------ calendar

  static String calendarKey(DateTime start, DateTime end) => 'cal:${ymd(start)}:${ymd(end)}';

  Future<CalendarData> calendar(DateTime start, DateTime end) async {
    final data = await fetch(calendarKey(start, end), 'calendar.get_my_day', {'start_date': ymd(start), 'end_date': ymd(end)});
    return CalendarData.fromJson(Map<String, dynamic>.from(data as Map));
  }

  CalendarData? cachedCalendar(DateTime start, DateTime end) {
    final c = cached(calendarKey(start, end));
    return c == null ? null : CalendarData.fromJson(Map<String, dynamic>.from(c.data as Map));
  }

  Future<Map<String, Map<String, int>>> monthMarkers(DateTime month) async {
    final key = 'month:${DateFormat('yyyy-MM').format(month)}';
    final data = await fetch(key, 'calendar.get_month_markers', {'month': DateFormat('yyyy-MM').format(month)});
    return _markers(data);
  }

  Map<String, Map<String, int>>? cachedMonthMarkers(DateTime month) {
    final c = cached('month:${DateFormat('yyyy-MM').format(month)}');
    return c == null ? null : _markers(c.data);
  }

  Map<String, Map<String, int>> _markers(dynamic data) {
    final days = Map<String, dynamic>.from(((data as Map)['days'] as Map?) ?? const {});
    return days.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map).map((s, n) => MapEntry(s, (n as num).toInt()))));
  }

  // ------------------------------------------------------------ activities

  PageResult<Activity> _activityPage(dynamic data) {
    final m = Map<String, dynamic>.from(data as Map);
    return PageResult(
      ((m['items'] as List?) ?? const []).map((e) => Activity.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      m['next_cursor']?.toString(),
    );
  }

  Future<PageResult<Activity>> activities({required bool meetings, required String status, String? cursor}) async {
    final method = meetings ? 'activities.get_meetings' : 'activities.get_followups';
    final key = '${meetings ? 'meet' : 'fu'}:$status';
    final data = cursor == null
        ? await fetch(key, method, {'status': status, 'page_size': 30})
        : await api.get(method, {'status': status, 'cursor': cursor, 'page_size': 30});
    return _activityPage(data);
  }

  PageResult<Activity>? cachedActivities({required bool meetings, required String status}) {
    final c = cached('${meetings ? 'meet' : 'fu'}:$status');
    return c == null ? null : _activityPage(c.data);
  }

  Future<Activity> activity(String id) async {
    final data = await fetch('act:$id', 'activities.get_detail', {'activity_id': id});
    return Activity.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Activity? cachedActivity(String id) {
    final c = cached('act:$id');
    return c == null ? null : Activity.fromJson(Map<String, dynamic>.from(c.data as Map));
  }

  Future<Activity> createActivity(Map<String, dynamic> payload) async {
    final data = await api.post('activities.create_activity', payload);
    return Activity.fromJson(Map<String, dynamic>.from((data as Map)['activity'] as Map));
  }

  Future<void> deleteActivity(String id, {String? reason}) =>
      api.post('activities.delete_activity', {'activity_id': id, 'reason': reason});

  /// Edit an open follow-up / meeting. Only the keys given are changed.
  Future<Activity> updateActivity(String id, Map<String, dynamic> values) async {
    final data = await api.post('activities.update_activity', {'activity_id': id, ...values});
    return Activity.fromJson(Map<String, dynamic>.from((data as Map)['activity'] as Map));
  }

  Future<Activity> updateStatus(String id, String status, {String? outcome, String? notes}) async {
    final data = await api.post('activities.update_status', {'activity_id': id, 'status': status, 'outcome': outcome, 'notes': notes});
    return Activity.fromJson(Map<String, dynamic>.from((data as Map)['activity'] as Map));
  }

  Future<Activity> reschedule(String id, DateTime start, DateTime? end, String? reason) async {
    final data = await api.post('activities.reschedule_activity', {
      'activity_id': id,
      'new_start_datetime': _iso(start),
      'new_end_datetime': end == null ? null : _iso(end),
      'reason': reason,
    });
    return Activity.fromJson(Map<String, dynamic>.from((data as Map)['activity'] as Map));
  }

  Future<void> addNote(String id, String note) => api.post('activities.add_note', {'activity_id': id, 'note': note});

  Future<void> logContact(String id, String channel) =>
      api.post('activities.log_contact', {'activity_id': id, 'channel': channel});

  // ------------------------------------------------------------ customers

  PageResult<Party> _partyPage(dynamic data) {
    final m = Map<String, dynamic>.from(data as Map);
    return PageResult(
      ((m['items'] as List?) ?? const []).map((e) => Party.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      m['next_cursor']?.toString(),
    );
  }

  Future<PageResult<Party>> searchParties(String query, String kind, {String? cursor}) async {
    final params = {'query': query, 'kind': kind, 'cursor': cursor, 'page_size': 30};
    // Only the default (empty search) first page is cached, to keep customer data on the phone minimal.
    final data = (query.isEmpty && cursor == null)
        ? await fetch('cust:$kind', 'customers.search', params)
        : await api.get('customers.search', params);
    return _partyPage(data);
  }

  PageResult<Party>? cachedParties(String kind) {
    final c = cached('cust:$kind');
    return c == null ? null : _partyPage(c.data);
  }

  Future<Map<String, dynamic>> partyDetail(String doctype, String name) async {
    final data = await api.get('customers.get_detail', {'doctype': doctype, 'name': name});
    return Map<String, dynamic>.from(data as Map);
  }

  // ------------------------------------------------------------ trials

  Future<List<Booking>> bookings(String status) async {
    final data = await fetch('trials:$status', 'trials.list_bookings', {'status': status, 'page_size': 50});
    return _bookings(data);
  }

  List<Booking>? cachedBookings(String status) {
    final c = cached('trials:$status');
    return c == null ? null : _bookings(c.data);
  }

  List<Booking> _bookings(dynamic data) => (((data as Map)['items'] as List?) ?? const [])
      .map((e) => Booking.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();

  Future<Booking> booking(String id) async {
    final data = await api.get('trials.get_booking_detail', {'booking_id': id});
    return Booking.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<Map<String, String>>> trainers() async {
    final data = await api.get('trials.get_trainers');
    return (((data as Map)['items'] as List?) ?? const [])
        .map((e) => {'id': (e as Map)['id'].toString(), 'name': e['name'].toString()})
        .toList();
  }

  /// Checks an exact time typed by hand (e.g. 10:15 - 11:30) and returns it as a bookable slot.
  Future<TrainerSlot> checkTrainerTime(String trainer, DateTime start, DateTime end) async {
    final data = await api.get('trials.check_time', {'trainer': trainer, 'start': iso(start), 'end': iso(end)});
    return TrainerSlot.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<TrainerSlot>> slots(DateTime from, DateTime to, {String? trainer, String? bookingType}) async {
    final data = await api.get('trials.get_available_slots', {
      'start_date': ymd(from),
      'end_date': ymd(to),
      'trainer': trainer,
      'booking_type': bookingType,
    });
    return (((data as Map)['items'] as List?) ?? const [])
        .map((e) => TrainerSlot.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Books the trial: the chosen session, plus (for a multi-day trial) the same time on each
  /// following day the trainer works. Returns the booking and the days that couldn't be booked.
  Future<(Booking, List<Map<String, dynamic>>)> book({
    required String slotId,
    String? customer,
    String? lead,
    required String bookingType,
    String? notes,
    required String idempotencyKey,
    int trialDays = 1,
  }) async {
    final data = Map<String, dynamic>.from(await api.post('trials.book_trial', {
      'trainer_slot': slotId,
      'customer': customer,
      'lead': lead,
      'booking_type': bookingType,
      'notes': notes,
      'idempotency_key': idempotencyKey,
      'trial_days': trialDays,
    }) as Map);
    final skipped = ((data['skipped'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return (Booking.fromJson(Map<String, dynamic>.from(data['booking'] as Map)), skipped);
  }

  Future<Booking> addTrialSession(String bookingId, String slotId, String idempotencyKey) async {
    final data = await api.post('trials.add_trial_session', {
      'booking_id': bookingId,
      'trainer_slot': slotId,
      'idempotency_key': idempotencyKey,
    });
    return Booking.fromJson(Map<String, dynamic>.from((data as Map)['booking'] as Map));
  }

  Future<Booking> setTrialDays(String bookingId, int days) async {
    final data = await api.post('trials.set_trial_days', {'booking_id': bookingId, 'days': days});
    return Booking.fromJson(Map<String, dynamic>.from((data as Map)['booking'] as Map));
  }

  Future<Booking> rescheduleBooking(String id, String newSlot, String? reason) async {
    final data = await api.post('trials.reschedule_booking', {'booking_id': id, 'new_slot_id': newSlot, 'reason': reason});
    return Booking.fromJson(Map<String, dynamic>.from((data as Map)['booking'] as Map));
  }

  Future<Booking> cancelBooking(String id, String? reason) async {
    final data = await api.post('trials.cancel_booking', {'booking_id': id, 'reason': reason});
    return Booking.fromJson(Map<String, dynamic>.from((data as Map)['booking'] as Map));
  }

  Future<Booking> completeBooking(String id, String? notes) async {
    final data = await api.post('trials.complete_booking', {'booking_id': id, 'completion_notes': notes});
    return Booking.fromJson(Map<String, dynamic>.from((data as Map)['booking'] as Map));
  }

  /// ERP customer/lead for this number, else the Google Maps business (server-side lookup).
  Future<NumberLookup> lookupNumber(String phone) async =>
      NumberLookup.fromJson(Map<String, dynamic>.from(await api.get('customers.lookup_number', {'phone': phone}) as Map));

  /// How many leads this session created (the caller-ID numbers are refreshed after a new one).
  int leadsCreated = 0;

  /// Creates a CRM Lead for an unknown number (or returns the existing one - never duplicates).
  Future<Party> createLead({required String phone, required String name, GooglePlace? google}) async {
    leadsCreated++;
    final data = Map<String, dynamic>.from(await api.post('customers.create_lead', {
      'phone': phone,
      'name': name,
      'address': google?.address,
      'maps_url': google?.mapsUrl,
      'place_id': google?.placeId,
    }) as Map);
    return Party.fromJson(Map<String, dynamic>.from(data['party'] as Map));
  }

  /// A business shared from Google Search / Maps -> phone number, name, ERP party.
  Future<SharedPlace> resolveShared(String text) async =>
      SharedPlace.fromJson(Map<String, dynamic>.from(await api.post('customers.resolve_shared', {'text': text}) as Map));

  /// Phone numbers of visible customers / leads / deals, for the caller pop-up.
  Future<List<Map<String, dynamic>>> phoneDirectory() async {
    final data = Map<String, dynamic>.from(await api.get('customers.phone_directory') as Map);
    return ((data['items'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Work calls from the phone's call history -> ERPNext call log (Calling Activity report).
  /// Editable fields of a customer / lead / deal (decided by the server).
  Future<List<EditField>> editForm(String doctype, String name) async {
    final data = Map<String, dynamic>.from(await api.get('customers.edit_form', {'doctype': doctype, 'name': name}) as Map);
    return ((data['fields'] as List?) ?? const []).map((e) => EditField.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> updateParty(String doctype, String name, Map<String, dynamic> values) =>
      api.post('customers.update_party', {'doctype': doctype, 'name': name, 'values': jsonEncode(values)});

  Future<Map<String, dynamic>> syncCalls(List<Map<String, dynamic>> calls) async =>
      Map<String, dynamic>.from(await api.post('calls.sync', {'calls': calls}) as Map);

  /// Automatic WhatsApp messages for this party since [since]: {enabled, items: [{status, title, error}]}.
  Future<Map<String, dynamic>> whatsappStatus(String doctype, String name, DateTime since) async =>
      Map<String, dynamic>.from(await api.get('calls.whatsapp_status', {
        'doctype': doctype,
        'name': name,
        'since': since.toUtc().toIso8601String(),
      }) as Map);

  // ------------------------------------------------------------ notes

  Future<List<Note>> partyNotes(String doctype, String name) async {
    final data = Map<String, dynamic>.from(await api.get('notes.get_list', {'doctype': doctype, 'name': name}) as Map);
    return ((data['items'] as List?) ?? const [])
        .map((e) => Note.fromJson(Map<String, dynamic>.from(e as Map), partyDoctype: doctype))
        .toList();
  }

  Future<Note> addPartyNote(String doctype, String name, String text) async => Note.fromJson(
      Map<String, dynamic>.from(await api.post('notes.add', {'doctype': doctype, 'name': name, 'text': text}) as Map));

  Future<Note> updatePartyNote(String id, String text) async =>
      Note.fromJson(Map<String, dynamic>.from(await api.post('notes.update', {'id': id, 'text': text}) as Map));

  Future<void> deletePartyNote(String id) => api.post('notes.delete', {'id': id});

  // ------------------------------------------------------------ call recordings

  Future<PageResult<CallRecording>> recordings({String? partyDoctype, String? party, String? cursor}) async {
    final data = Map<String, dynamic>.from(await api.get('recordings.get_list', {
      'party_doctype': partyDoctype,
      'party': party,
      'cursor': cursor,
      'page_size': 30,
    }) as Map);
    return PageResult(
      ((data['items'] as List?) ?? const []).map((e) => CallRecording.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      data['next_cursor']?.toString(),
    );
  }

  Future<CallRecording> uploadRecording(Map<String, dynamic> fields, String filePath) async {
    final data = await api.upload('recordings.upload', fields, filePath);
    return CallRecording.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> deleteRecording(String id) => api.post('recordings.delete', {'name': id});

  /// Downloads (once) to the cache and returns the local file path for playback.
  Future<String> recordingFile(CallRecording r) async {
    final path = '${Directory.systemTemp.path}/hm-rec-${r.id}.${r.ext ?? 'm4a'}';
    final f = File(path);
    if (await f.exists() && await f.length() > 0) return path;
    await api.downloadTo('recordings.download', {'name': r.id}, path);
    return path;
  }

  // ------------------------------------------------------------ notifications

  Future<List<AppNotice>> notifications() async {
    final data = await fetch('notices', 'devices.get_notification_history', {'page_size': 50});
    return (((data as Map)['items'] as List?) ?? const [])
        .map((e) => AppNotice.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> preferences() async =>
      Map<String, dynamic>.from(await api.get('devices.get_notification_preferences') as Map);

  Future<void> savePreferences(Map<String, dynamic> prefs) => api.post('devices.update_notification_preferences', prefs);

  /// Local time with offset, e.g. 2026-10-13T10:30:00+05:30 (never ambiguous for the server).
  static String _iso(DateTime d) {
    final local = d.toLocal();
    final off = local.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final h = off.inHours.abs().toString().padLeft(2, '0');
    final m = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '${DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(local)}$sign$h:$m';
  }

  static String iso(DateTime d) => _iso(d);

  // ------------------------------------------------------------ WhatsApp chats

  Future<PageResult<WaChat>> waChats({String? query, bool unreadOnly = false, String? cursor}) async {
    final data = Map<String, dynamic>.from(await api.get('whatsapp.chats', {
      'query': query,
      'unread': unreadOnly ? 1 : null,
      'cursor': cursor,
      'page_size': 30,
    }) as Map);
    final items = ((data['items'] as List?) ?? const []).map((e) => WaChat.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    if (query == null && !unreadOnly && cursor == null) await cache.write('wa:chats', data);
    return PageResult(items, str(data['next_cursor']));
  }

  List<WaChat>? cachedWaChats() {
    final c = cache.read('wa:chats');
    if (c == null) return null;
    final items = ((c.data as Map?)?['items'] as List?) ?? const [];
    return items.map((e) => WaChat.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<int> waUnreadChats() async {
    final data = Map<String, dynamic>.from(await api.get('whatsapp.unread_count') as Map);
    return (data['chats'] as num?)?.toInt() ?? 0;
  }

  Future<WaThread> waMessages(String phone, {DateTime? before}) async {
    final data = await api.get('whatsapp.messages', {
      'phone': phone,
      'before': before?.toUtc().toIso8601String(),
    });
    return WaThread.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> waMarkRead(String phone) => api.post('whatsapp.mark_read', {'phone': phone});

  (WaMessage, WaChat) _sent(dynamic data) {
    final m = Map<String, dynamic>.from(data as Map);
    return (
      WaMessage.fromJson(Map<String, dynamic>.from(m['message'] as Map)),
      WaChat.fromJson(Map<String, dynamic>.from(m['chat'] as Map)),
    );
  }

  Future<(WaMessage, WaChat)> waSendText(String phone, String text, {String? replyTo}) async =>
      _sent(await api.post('whatsapp.send_text', {'phone': phone, 'text': text, 'reply_to': replyTo}));

  Future<(WaMessage, WaChat)> waSendMedia(String phone, String path, {String? caption, String? replyTo}) async =>
      _sent(await api.upload('whatsapp.send_media', {'phone': phone, 'caption': caption, 'reply_to': replyTo}, path));

  Future<List<WaTemplate>> waTemplates(String? phone) async {
    final data = Map<String, dynamic>.from(await api.get('whatsapp.templates', {'phone': phone}) as Map);
    return ((data['items'] as List?) ?? const []).map((e) => WaTemplate.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<(WaMessage, WaChat)> waSendTemplate(String phone, String template, List<String> params, {String? picturePath}) async {
    final fields = {'phone': phone, 'template': template, 'params': jsonEncode(params)};
    if (picturePath != null) return _sent(await api.upload('whatsapp.send_template', fields, picturePath));
    return _sent(await api.post('whatsapp.send_template', fields));
  }

  /// Downloads (once) a message's photo / voice / file and returns the local path.
  Future<String> waMediaFile(WaMessage m) async {
    final ext = (m.media?.ext ?? 'bin').replaceAll(RegExp(r'[^a-z0-9]'), '');
    final path = '${Directory.systemTemp.path}/hm-wa-${m.id}.$ext';
    final f = File(path);
    if (await f.exists() && await f.length() > 0) return path;
    await api.downloadTo('whatsapp.media', {'message': m.id}, path, what: 'file');
    return path;
  }

  // ------------------------------------------------------------ calls list

  Future<CallsPage> calls({String scope = 'mine', String filter = 'all', String? query, String? cursor}) async {
    final key = 'calls:$scope:$filter';
    final params = {'scope': scope, 'filter': filter, 'query': query, 'cursor': cursor, 'page_size': 40};
    final plain = (query == null || query.isEmpty) && cursor == null;
    final data = plain ? await fetch(key, 'calls.list_calls', params) : await api.get('calls.list_calls', params);
    return CallsPage.fromJson(Map<String, dynamic>.from(data as Map));
  }

  CallsPage? cachedCalls(String scope, String filter) {
    final c = cache.read('calls:$scope:$filter');
    return c == null ? null : CallsPage.fromJson(Map<String, dynamic>.from(c.data as Map));
  }

  Future<String> callRecordingFile(String id, String? ext) async {
    final path = '${Directory.systemTemp.path}/hm-rec-$id.${ext ?? 'm4a'}';
    final f = File(path);
    if (await f.exists() && await f.length() > 0) return path;
    await api.downloadTo('recordings.download', {'name': id}, path);
    return path;
  }

  // ------------------------------------------------------------ development tasks

  Future<DevPage> devTasks({String scope = 'mine', String filter = 'open', String? cursor, String kind = 'dev', String? team}) async {
    final params = {'scope': scope, 'filter': filter, 'cursor': cursor, 'page_size': 30, 'kind': kind, 'team': team};
    final key = 'dev:$kind:$scope:$filter:${team ?? ''}';
    final data = Map<String, dynamic>.from(
        (cursor == null ? await fetch(key, 'development.list_tasks', params) : await api.get('development.list_tasks', params)) as Map);
    final counts = Map<String, dynamic>.from((data['counts'] as Map?) ?? const {});
    return DevPage(
      ((data['items'] as List?) ?? const []).map((e) => DevTask.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      data['next_cursor']?.toString(),
      (counts['open'] as num?)?.toInt() ?? 0,
      (counts['late'] as num?)?.toInt() ?? 0,
      teams: ((data['teams'] as List?) ?? const []).map((e) => e.toString()).toList(),
    );
  }

  Future<DevTask> devTask(String id, {String kind = 'dev'}) async =>
      DevTask.fromJson(Map<String, dynamic>.from(await api.get('development.get_task', {'task_id': id, 'kind': kind}) as Map));

  /// People who can get this kind of work, and (team tasks) the teams.
  Future<(List<Map<String, String>>, List<String>)> developers({String kind = 'dev'}) async {
    final data = Map<String, dynamic>.from(await api.get('development.developers', {'kind': kind}) as Map);
    final people = ((data['items'] as List?) ?? const [])
        .map((e) => {'id': (e as Map)['id'].toString(), 'name': e['name'].toString()})
        .toList();
    return (people, ((data['teams'] as List?) ?? const []).map((e) => e.toString()).toList());
  }

  Future<DevTask> devCreate(Map<String, dynamic> values, {String kind = 'dev'}) async =>
      DevTask.fromJson(Map<String, dynamic>.from(await api.post('development.create_task', {...values, 'kind': kind}) as Map));

  Future<DevTask> devUpdate(String id, Map<String, dynamic> values, {String kind = 'dev'}) async => DevTask.fromJson(
      Map<String, dynamic>.from(await api.post('development.update_task', {'task_id': id, ...values, 'kind': kind}) as Map));

  // ------------------------------------------------------------ files & voice notes

  Future<List<Attachment>> attachments(String doctype, String name) async =>
      attachmentsFrom((await api.get('attachments.list_files', {'doctype': doctype, 'name': name}) as Map)['items']);

  Future<Attachment> uploadAttachment(String doctype, String name, String path, {bool voice = false}) async =>
      Attachment.fromJson(Map<String, dynamic>.from(
          await api.upload('attachments.upload', {'doctype': doctype, 'name': name, if (voice) 'voice': 1}, path) as Map));

  Future<void> deleteAttachment(String id) => api.post('attachments.delete_file', {'file_id': id});

  Future<String> attachmentFile(Attachment a) async {
    final path = '${Directory.systemTemp.path}/hm-att-${a.id}.${a.ext.replaceAll(RegExp(r'[^a-z0-9]'), '')}';
    final f = File(path);
    if (await f.exists() && await f.length() > 0) return path;
    await api.downloadTo('attachments.file', {'file_id': a.id}, path, what: 'file');
    return path;
  }

  // ------------------------------------------------------------ app suggestions

  Future<PageResult<Suggestion>> suggestions({String filter = 'open', String sort = 'top', String? cursor}) async {
    final data = Map<String, dynamic>.from(await api.get('feedback.list_feedback', {'filter': filter, 'sort': sort, 'cursor': cursor, 'page_size': 30}) as Map);
    return PageResult(
      ((data['items'] as List?) ?? const []).map((e) => Suggestion.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      data['next_cursor']?.toString(),
    );
  }

  Future<Suggestion> suggestion(String id) async =>
      Suggestion.fromJson(Map<String, dynamic>.from(await api.get('feedback.get_feedback', {'feedback_id': id}) as Map));

  Future<Suggestion> createSuggestion(Map<String, dynamic> values) async =>
      Suggestion.fromJson(Map<String, dynamic>.from(await api.post('feedback.create_feedback', values) as Map));

  Future<Suggestion> voteSuggestion(String id) async =>
      Suggestion.fromJson(Map<String, dynamic>.from(await api.post('feedback.vote', {'feedback_id': id}) as Map));

  Future<Suggestion> updateSuggestion(String id, Map<String, dynamic> values) async =>
      Suggestion.fromJson(Map<String, dynamic>.from(await api.post('feedback.update_feedback', {'feedback_id': id, ...values}) as Map));

  // ------------------------------------------------------------ concerns

  Future<Map<String, dynamic>> concernOptions() async => Map<String, dynamic>.from(await api.get('concerns.options') as Map);

  Future<PageResult<Concern>> concerns({String scope = 'mine', String? cursor}) async {
    final data = Map<String, dynamic>.from(await api.get('concerns.list_concerns', {'scope': scope, 'cursor': cursor, 'page_size': 30}) as Map);
    return PageResult(
      ((data['items'] as List?) ?? const []).map((e) => Concern.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      data['next_cursor']?.toString(),
    );
  }

  Future<Concern> concern(String id) async =>
      Concern.fromJson(Map<String, dynamic>.from(await api.get('concerns.get_concern', {'concern_id': id}) as Map));

  Future<Concern> createConcern(Map<String, dynamic> values) async =>
      Concern.fromJson(Map<String, dynamic>.from(await api.post('concerns.create_concern', values) as Map));

  Future<Concern> respondConcern(String id, {String? response, String? status}) async => Concern.fromJson(
      Map<String, dynamic>.from(await api.post('concerns.respond', {'concern_id': id, 'response': response, 'status': status}) as Map));

  Future<Concern> addToConcern(String id, String text) async =>
      Concern.fromJson(Map<String, dynamic>.from(await api.post('concerns.add_detail', {'concern_id': id, 'text': text}) as Map));

  // ------------------------------------------------------------ call targets

  Future<TargetProgress?> myTarget() async {
    final data = Map<String, dynamic>.from(await fetch('target:mine', 'targets.my_target', const {}) as Map);
    return TargetProgress.fromJson(data['target']);
  }

  TargetProgress? cachedTarget() {
    final c = cache.read('target:mine');
    return c == null ? null : TargetProgress.fromJson((c.data as Map)['target']);
  }

  Future<List<CallerTarget>> callerTargets() async {
    final data = Map<String, dynamic>.from(await api.get('targets.list_targets') as Map);
    return ((data['items'] as List?) ?? const []).map((e) => CallerTarget.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> saveCallerTarget(Map<String, dynamic> values) => api.post('targets.save_target', values);

  // ------------------------------------------------------------ daily report

  Future<DailyReport> dailyReport(DateTime day, {String? user}) async => DailyReport.fromJson(
      Map<String, dynamic>.from(await api.get('reports.get_report', {'date': ymd(day), 'user': user}) as Map));

  Future<List<DailyReport>> teamReport(DateTime day) async {
    final data = Map<String, dynamic>.from(await api.get('reports.team_report', {'date': ymd(day)}) as Map);
    return ((data['items'] as List?) ?? const []).map((e) => DailyReport.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }
}
