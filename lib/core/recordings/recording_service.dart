import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/models.dart';
import '../api/api_client.dart';
import '../phone/direct_call.dart';
import '../repository.dart';

/// A call placed from Hipersign, waiting for (or holding) the phone's recording of it.
class CallEntry {
  CallEntry({
    required this.id,
    required this.number,
    required this.startedAt,
    this.partyDoctype,
    this.party,
    this.partyName,
    this.activity,
    this.status = CallEntry.waiting,
    this.uri,
    this.fileName,
    this.durationMs = 0,
    this.size = 0,
    this.serverId,
    this.error,
    this.attempts = 0,
  });

  static const waiting = 'waiting'; // call made, recording not found yet
  static const found = 'found'; // recording found, ready to upload
  static const unlinked = 'unlinked'; // recording found, but no customer chosen
  static const uploading = 'uploading';
  static const uploaded = 'uploaded';
  static const failed = 'failed';
  static const notFound = 'not_found';

  final String id; // also the upload's client key (retries never duplicate)
  final String number;
  final DateTime startedAt;
  String? partyDoctype;
  String? party;
  String? partyName;
  String? activity;
  String status;
  String? uri;
  String? fileName;
  int durationMs;
  int size;
  String? serverId;
  String? error;
  int attempts;

  bool get hasParty => party != null && partyDoctype != null;
  bool get hasRecording => uri != null;
  String get title => partyName ?? number;

  String get statusLabel => switch (status) {
        waiting => 'Waiting for the phone\'s recording',
        found => 'Ready to upload',
        unlinked => 'Choose the customer to save it',
        uploading => 'Uploading...',
        uploaded => 'Saved to ERP',
        failed => error ?? 'Upload failed - will try again',
        notFound => 'No recording found',
        _ => status,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'started_at': startedAt.millisecondsSinceEpoch,
        'party_doctype': partyDoctype,
        'party': party,
        'party_name': partyName,
        'activity': activity,
        'status': status,
        'uri': uri,
        'file_name': fileName,
        'duration_ms': durationMs,
        'size': size,
        'server_id': serverId,
        'error': error,
        'attempts': attempts,
      };

  factory CallEntry.fromJson(Map<String, dynamic> j) => CallEntry(
        id: j['id'].toString(),
        number: j['number']?.toString() ?? '',
        startedAt: DateTime.fromMillisecondsSinceEpoch((j['started_at'] as num).toInt()),
        partyDoctype: j['party_doctype'] as String?,
        party: j['party'] as String?,
        partyName: j['party_name'] as String?,
        activity: j['activity'] as String?,
        status: j['status']?.toString() ?? waiting,
        uri: j['uri'] as String?,
        fileName: j['file_name'] as String?,
        durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
        size: (j['size'] as num?)?.toInt() ?? 0,
        serverId: j['server_id'] as String?,
        error: j['error'] as String?,
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      );
}

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// Which of the phone's audio files is the recording of a call to [number] started at
/// [startedAt]? Files must appear between the call start and the next call made from the
/// app (or 4 hours). A file whose name contains the number wins; otherwise the first file
/// saved in a call-recording folder ("call" in its folder or name).
PhoneAudioFile? pickRecording({
  required String number,
  required DateTime startedAt,
  DateTime? nextCallAt,
  required List<PhoneAudioFile> files,
  Set<String> used = const {},
}) {
  final windowStart = startedAt.subtract(const Duration(seconds: 15));
  final windowEnd = nextCallAt ?? startedAt.add(const Duration(hours: 4));
  final tail = _digits(number);
  final key = tail.length >= 7 ? tail.substring(tail.length - 7) : null;
  final candidates = files
      .where((f) => !used.contains(f.uri) && f.size > 0 && !f.added.isBefore(windowStart) && f.added.isBefore(windowEnd))
      .toList()
    ..sort((a, b) => a.added.compareTo(b.added));
  if (key != null) {
    for (final f in candidates) {
      if (_digits(f.name).contains(key)) return f;
    }
  }
  for (final f in candidates) {
    if ('${f.path}/${f.name}'.toLowerCase().contains('call')) return f;
  }
  return null;
}

/// Remembers calls made from the app, finds the phone's own recording of each call
/// (Android's built-in call recorder saves them as audio files) and uploads it to
/// ERPNext linked to the customer and activity.
class RecordingService extends ChangeNotifier {
  RecordingService._();
  static final RecordingService instance = RecordingService._();

  static const _maxEntries = 300;
  static const _giveUpAfter = Duration(hours: 6);
  static const _maxAttempts = 6;

  bool enabled = false;
  String? _user;
  List<CallEntry> _entries = [];
  Set<String> _used = {};
  bool _loaded = false;
  bool _syncing = false;
  bool _askedThisSession = false;

  /// "granted" | "denied" | "blocked" | "unsupported" | null (not checked yet).
  String? permission;

  List<CallEntry> get entries => List.unmodifiable(_entries);

  /// Calls whose recording is not in ERP yet (newest first).
  List<CallEntry> get pending =>
      _entries.where((e) => e.status != CallEntry.uploaded).toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  bool get supported => Platform.isAndroid;

  String get _key => 'hm_call_log_v1:${_user ?? '-'}';
  String get _usedKey => 'hm_used_recordings_v1:${_user ?? '-'}';

  Future<void> bind(String user, {required bool enabled}) async {
    this.enabled = enabled && supported;
    if (_user == user && _loaded) return;
    _user = user;
    _loaded = false;
    await _load();
    notifyListeners();
  }

  Future<void> _load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_key);
      _entries = raw == null
          ? []
          : (jsonDecode(raw) as List).map((e) => CallEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      _used = (prefs.getStringList(_usedKey) ?? const []).toSet();
      for (final e in _entries.where((e) => e.status == CallEntry.uploading)) {
        e.status = CallEntry.found; // app was closed mid-upload
      }
    } catch (_) {
      _entries = [];
      _used = {};
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    _entries.removeWhere((e) =>
        (e.status == CallEntry.uploaded || e.status == CallEntry.notFound) && e.startedAt.isBefore(cutoff));
    _entries.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    if (_entries.length > _maxEntries) _entries = _entries.sublist(_entries.length - _maxEntries);
    if (_used.length > 600) _used = _used.skip(_used.length - 600).toSet();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    await prefs.setStringList(_usedKey, _used.toList());
  }

  /// Called just before Hipersign places a call.
  Future<void> noteCall({
    required String number,
    String? partyDoctype,
    String? party,
    String? partyName,
    String? activity,
  }) async {
    if (!enabled || _user == null) return;
    await _load();
    _entries.add(CallEntry(
      id: '${_user!.hashCode.toRadixString(16)}-${DateTime.now().millisecondsSinceEpoch}-${randomKey(4)}',
      number: number,
      startedAt: DateTime.now(),
      partyDoctype: party == null ? null : partyDoctype,
      party: party,
      partyName: partyName,
      activity: activity,
    ));
    await _save();
    notifyListeners();
  }

  /// Ask for audio access (shows Android's dialog unless the user blocked it).
  Future<String> requestPermission() async {
    permission = await audioPermission(request: true);
    notifyListeners();
    return permission!;
  }

  /// Find recordings for waiting calls and upload what is ready. Safe to call often.
  Future<void> sync(Repository repo, {bool askPermission = false}) async {
    if (!enabled || _syncing || _user == null) return;
    _syncing = true;
    try {
      await _load();
      final waiting = _entries.where((e) => e.status == CallEntry.waiting).toList();
      permission = await audioPermission();
      if (waiting.isNotEmpty && permission == 'denied' && askPermission && !_askedThisSession) {
        _askedThisSession = true;
        permission = await audioPermission(request: true);
      }
      if (waiting.isNotEmpty && permission == 'granted') await _match(waiting);
      await _uploadReady(repo);
    } finally {
      _syncing = false;
      await _save();
      notifyListeners();
    }
  }

  Future<void> _match(List<CallEntry> waiting) async {
    final all = [..._entries]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    waiting.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final now = DateTime.now();
    List<PhoneAudioFile> files;
    try {
      files = await findPhoneRecordings(waiting.first.startedAt.subtract(const Duration(seconds: 30)), now);
    } catch (_) {
      return;
    }
    for (final e in waiting) {
      final next = all.where((o) => o.startedAt.isAfter(e.startedAt)).map((o) => o.startedAt).firstOrNull;
      final pick = pickRecording(number: e.number, startedAt: e.startedAt, nextCallAt: next, files: files, used: _used);

      if (pick != null) {
        _used.add(pick.uri);
        e
          ..uri = pick.uri
          ..fileName = pick.name
          ..durationMs = pick.durationMs
          ..size = pick.size
          ..status = e.hasParty ? CallEntry.found : CallEntry.unlinked;
      } else if (now.difference(e.startedAt) > _giveUpAfter) {
        e.status = CallEntry.notFound;
      }
    }
  }

  Future<void> _uploadReady(Repository repo) async {
    final ready = _entries
        .where((e) =>
            e.hasRecording && e.hasParty &&
            (e.status == CallEntry.found || (e.status == CallEntry.failed && e.attempts < _maxAttempts)))
        .toList();
    for (final e in ready) {
      await _upload(repo, e);
    }
  }

  Future<void> _upload(Repository repo, CallEntry e) async {
    e
      ..status = CallEntry.uploading
      ..error = null;
    notifyListeners();
    String? local;
    try {
      local = await copyPhoneRecording(e.uri!, e.fileName ?? 'recording.m4a');
      final saved = await repo.uploadRecording({
        'party_doctype': e.partyDoctype,
        'party': e.party,
        'phone': e.number,
        'started_at': e.startedAt.toUtc().toIso8601String(),
        'duration': (e.durationMs / 1000).round(),
        'activity': e.activity,
        'client_key': e.id,
        'source_name': e.fileName,
      }, local);
      e
        ..serverId = saved.id
        ..partyName = saved.partyName
        ..status = CallEntry.uploaded;
    } on ApiException catch (err) {
      if (err.isNetwork || err.code == 'RATE_LIMITED') {
        e.status = CallEntry.found; // try again on the next sync, no attempt used
      } else {
        e
          ..attempts += 1
          ..status = CallEntry.failed
          ..error = err.message;
      }
    } catch (_) {
      e
        ..attempts = _maxAttempts
        ..status = CallEntry.failed
        ..error = 'The recording is no longer on this phone.';
    } finally {
      if (local != null) {
        try {
          await File(local).delete();
        } catch (_) {}
      }
    }
  }

  /// Link a recording that has no customer yet, then upload it.
  Future<void> link(Repository repo, CallEntry e, Party p) async {
    e
      ..partyDoctype = p.doctype
      ..party = p.id
      ..partyName = p.name
      ..status = e.hasRecording ? CallEntry.found : CallEntry.waiting
      ..attempts = 0;
    await _save();
    notifyListeners();
    if (e.hasRecording) {
      await _upload(repo, e);
      await _save();
      notifyListeners();
    }
  }

  Future<void> retry(Repository repo, CallEntry e) async {
    e.attempts = 0;
    if (e.hasRecording && e.hasParty) {
      await _upload(repo, e);
    } else if (!e.hasRecording) {
      e.status = CallEntry.waiting;
      await sync(repo);
    }
    await _save();
    notifyListeners();
  }

  Future<void> dismiss(CallEntry e) async {
    _entries.removeWhere((x) => x.id == e.id);
    await _save();
    notifyListeners();
  }

  /// Local copy for playing a recording that is not uploaded yet.
  Future<String> localFile(CallEntry e) => copyPhoneRecording(e.uri!, 'play-${e.fileName ?? 'recording.m4a'}');
}
