import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../core/repository.dart';
import '../../features/recordings/recording_widgets.dart';
import '../models/team.dart';
import '../models/models.dart';
import 'common.dart';

/// A file chosen on the phone, not uploaded yet (forms upload them after saving).
class PendingFile {
  PendingFile(this.path, {this.voice = false, this.seconds});
  final String path;
  final bool voice;
  final int? seconds;

  String get name => voice ? 'Voice note${seconds != null ? ' (${fmtDuration(seconds!)})' : ''}' : path.split('/').last;
}

String fileSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

IconData _icon(String kind) => switch (kind) {
      'audio' => Icons.mic,
      'image' => Icons.image_outlined,
      'video' => Icons.movie_outlined,
      _ => Icons.insert_drive_file_outlined,
    };

/// Largest file the server takes (its web server limit).
const maxUploadMb = 45;

/// Record voice / camera / gallery (several photos / videos) / documents (several).
/// Returns an empty list when cancelled.
Future<List<PendingFile>> pickAttachments(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.mic, color: HsColors.danger), title: const Text('Record a voice note'), onTap: () => Navigator.pop(ctx, 'voice')),
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, 'camera')),
        ListTile(leading: const Icon(Icons.videocam_outlined), title: const Text('Record a video'), onTap: () => Navigator.pop(ctx, 'camera_video')),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Photos / videos from gallery'),
          subtitle: const Text('Select several at once'),
          onTap: () => Navigator.pop(ctx, 'gallery'),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Documents (PDF, Excel, Word...)'),
          subtitle: const Text('Select several at once'),
          onTap: () => Navigator.pop(ctx, 'documents'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return const [];
  try {
    final picker = ImagePicker();
    switch (choice) {
      case 'voice':
        final v = await recordVoiceNote(context);
        return v == null ? const [] : [v];
      case 'camera':
        final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 2200);
        return x == null ? const [] : [PendingFile(x.path)];
      case 'camera_video':
        final x = await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 3));
        return x == null ? const [] : [PendingFile(x.path)];
      case 'gallery':
        final xs = await picker.pickMultipleMedia(imageQuality: 85, maxWidth: 2400);
        return [for (final x in xs) PendingFile(x.path)];
      case 'documents':
        if (!Platform.isAndroid) {
          showSnack('Documents can be added from the Android app.', error: true);
          return const [];
        }
        final paths = await const MethodChannel('hipersign/phone').invokeMethod<List<dynamic>>('pickDocuments');
        return [for (final p in paths ?? const []) PendingFile(p.toString())];
    }
  } on PlatformException catch (e) {
    showSnack(e.message ?? 'Could not open the camera / files.', error: true);
  }
  return const [];
}

/// Files over the upload limit are dropped with a message.
List<PendingFile> withinLimit(List<PendingFile> files) {
  final ok = <PendingFile>[];
  for (final f in files) {
    final mb = File(f.path).lengthSync() / (1024 * 1024);
    if (mb > maxUploadMb) {
      showSnack('${f.name} is too big (${mb.toStringAsFixed(0)} MB). Max $maxUploadMb MB - send a shorter video.', error: true);
    } else {
      ok.add(f);
    }
  }
  return ok;
}

/// Records a voice note in a sheet (tap to stop). Returns null when cancelled.
Future<PendingFile?> recordVoiceNote(BuildContext context) async {
  final recorder = AudioRecorder();
  try {
    if (!await recorder.hasPermission()) {
      showSnack('Allow the microphone for Hipersign to record voice notes.', error: true);
      return null;
    }
  } catch (_) {
    showSnack('Could not use the microphone.', error: true);
    return null;
  }
  if (!context.mounted) return null;
  final path = '${Directory.systemTemp.path}/note-${DateTime.now().millisecondsSinceEpoch}.m4a';
  final result = await showModalBottomSheet<PendingFile>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (ctx) => _Recorder(recorder: recorder, path: path),
  );
  try {
    await recorder.dispose();
  } catch (_) {}
  return result;
}

class _Recorder extends StatefulWidget {
  const _Recorder({required this.recorder, required this.path});
  final AudioRecorder recorder;
  final String path;

  @override
  State<_Recorder> createState() => _RecorderState();
}

class _RecorderState extends State<_Recorder> {
  final _started = DateTime.now();
  Timer? _timer;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    widget.recorder
        .start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1), path: widget.path)
        .then((_) {
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _ok = true);
    }).catchError((Object _) {
      if (mounted) Navigator.pop(context);
      showSnack('Could not start recording.', error: true);
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (DateTime.now().difference(_started) >= const Duration(minutes: 10)) _stop(true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _stop(bool keep) async {
    _timer?.cancel();
    final secs = DateTime.now().difference(_started).inSeconds;
    String? path;
    try {
      path = keep ? await widget.recorder.stop() : null;
      if (!keep) await widget.recorder.cancel();
    } catch (_) {}
    if (!mounted) return;
    if (keep && secs < 1) {
      showSnack('Too short - hold on a little longer.');
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, keep && path != null ? PendingFile(path, voice: true, seconds: secs) : null);
  }

  @override
  Widget build(BuildContext context) {
    final secs = DateTime.now().difference(_started).inSeconds;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.mic, size: 48, color: _ok ? HsColors.danger : HsColors.textSecondary),
          const SizedBox(height: 8),
          Text(_ok ? 'Recording...' : 'Starting...', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(fmtDuration(secs), style: const TextStyle(fontSize: 28, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _stop(false), icon: const Icon(Icons.delete_outline), label: const Text('Discard'))),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: HsColors.danger),
                onPressed: _ok ? () => _stop(true) : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop & keep'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Uploads files chosen in a form once the record exists, with a progress dialog (so nobody
/// taps Save again while a video uploads). Returns how many failed.
Future<int> uploadPending(Repository repo, String doctype, String name, List<PendingFile> files, {BuildContext? context}) async {
  final progress = ValueNotifier<String>('Uploading files...');
  final ctx = context ?? navigatorKey.currentContext;
  if (ctx != null && files.isNotEmpty) {
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Expanded(child: ValueListenableBuilder<String>(valueListenable: progress, builder: (_, t, _) => Text(t))),
          ]),
        ),
      ),
    );
  }
  var failed = 0;
  for (var i = 0; i < files.length; i++) {
    progress.value = 'Uploading ${i + 1} of ${files.length}: ${files[i].name}';
    try {
      await repo.uploadAttachment(doctype, name, files[i].path, voice: files[i].voice);
    } catch (_) {
      failed++;
    }
  }
  if (ctx != null && files.isNotEmpty && ctx.mounted) Navigator.of(ctx, rootNavigator: true).pop();
  if (failed > 0) showSnack('$failed file${failed > 1 ? 's' : ''} could not be uploaded - add again from the details.', error: true);
  return failed;
}

/// "Files & voice notes" for a form: chosen now, uploaded after saving.
class PendingAttachments extends StatelessWidget {
  const PendingAttachments({super.key, required this.files, required this.onChanged, this.title = 'Files & voice notes'});
  final List<PendingFile> files;
  final ValueChanged<List<PendingFile>> onChanged;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      Wrap(spacing: 8, children: [
        TextButton.icon(
          onPressed: () async {
            final f = await recordVoiceNote(context);
            if (f != null) onChanged([...files, f]);
          },
          icon: const Icon(Icons.mic, color: HsColors.danger),
          label: const Text('Voice'),
        ),
        TextButton.icon(
          onPressed: () async {
            final picked = withinLimit(await pickAttachments(context));
            if (picked.isNotEmpty) onChanged([...files, ...picked]);
          },
          icon: const Icon(Icons.attach_file),
          label: const Text('Photo / file'),
        ),
      ]),
      if (files.isEmpty)
        const Text('Explain by voice, or add photos / documents (optional).', style: TextStyle(color: HsColors.textSecondary, fontSize: 12.5)),
      for (final f in files)
        Card(
          elevation: 0,
          color: HsColors.card,
          margin: const EdgeInsets.only(top: 6),
          child: ListTile(
            dense: true,
            leading: Icon(f.voice ? Icons.mic : Icons.insert_drive_file_outlined, color: f.voice ? HsColors.danger : HsColors.navy),
            title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close),
              onPressed: () => onChanged([...files]..remove(f)),
            ),
          ),
        ),
    ]);
  }
}

/// Files and voice notes on a saved record: play / open, add more, remove your own.
class AttachmentsSection extends StatefulWidget {
  const AttachmentsSection({super.key, required this.doctype, required this.name, this.title = 'Files & voice notes', this.canAdd = true, this.initial});
  final String doctype;
  final String name;
  final String title;
  final bool canAdd;
  final List<Attachment>? initial;

  @override
  State<AttachmentsSection> createState() => _AttachmentsSectionState();
}

class _AttachmentsSectionState extends State<AttachmentsSection> {
  final _player = RecordingPlayer();
  List<Attachment>? _items;
  int _uploading = 0;
  String? _opening;

  @override
  void initState() {
    super.initState();
    _items = widget.initial;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Repository get _repo => context.read<SessionController>().repo;

  Future<void> _load() async {
    try {
      final items = await _repo.attachments(widget.doctype, widget.name);
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted && _items == null) setState(() => _items = const []);
      showSnack(e.message, error: true);
    }
  }

  Future<void> _add(PendingFile? f) async {
    if (f == null) return;
    setState(() => _uploading++);
    try {
      await _repo.uploadAttachment(widget.doctype, widget.name, f.path, voice: f.voice);
      showSnack(f.voice ? 'Voice note added' : 'File added');
      await _load();
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _uploading--);
    }
  }

  Future<void> _open(Attachment a) async {
    setState(() => _opening = a.id);
    try {
      final path = await _repo.attachmentFile(a);
      if (a.kind == 'image' && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(a.name)),
              body: Center(child: InteractiveViewer(child: Image.file(File(path)))),
            ),
          ),
        );
      } else {
        final r = await OpenFilex.open(path);
        if (r.type != ResultType.done) showSnack('No app on this phone can open this file.', error: true);
      }
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _delete(Attachment a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this file?'),
        content: Text(a.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteAttachment(a.id);
      await _load();
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<SessionController>().profile?.user;
    final items = _items;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700))),
        if (_uploading > 0) ...[
          const SizedBox(width: 8),
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
        if (widget.canAdd) ...[
          IconButton(
            tooltip: 'Record a voice note',
            onPressed: () async => _add(await recordVoiceNote(context)),
            icon: const Icon(Icons.mic, color: HsColors.danger),
          ),
          IconButton(
            tooltip: 'Add a file',
            onPressed: () async {
              for (final f in withinLimit(await pickAttachments(context))) {
                await _add(f);
              }
            },
            icon: const Icon(Icons.attach_file),
          ),
        ],
      ]),
      if (items == null) const LinearProgressIndicator(),
      if (items != null && items.isEmpty)
        const Text('Nothing added yet.', style: TextStyle(color: HsColors.textSecondary)),
      for (final a in items ?? const <Attachment>[])
        Card(
          elevation: 0,
          color: HsColors.card,
          margin: const EdgeInsets.only(top: 6),
          child: a.kind == 'audio'
              ? ListenableBuilder(
                  listenable: _player,
                  builder: (context, _) {
                    final playing = _player.isPlaying(a.id);
                    final loading = _player.loadingId == a.id;
                    return Column(children: [
                      ListTile(
                        leading: IconButton(
                          onPressed: () => _player.toggle(a.id, () => _repo.attachmentFile(a)),
                          icon: loading
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 34, color: HsColors.navy),
                        ),
                        title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text([if (a.by != null) a.by!, if (a.at != null) fmtDayTime(a.at)].join(' · ')),
                        onLongPress: a.byUser == me ? () => _delete(a) : null,
                      ),
                      if (_player.currentId == a.id && !loading)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: StreamBuilder<Duration>(
                            stream: _player.position,
                            builder: (context, snap) {
                              final total = _player.duration.inMilliseconds;
                              final pos = (snap.data ?? Duration.zero).inMilliseconds;
                              return Row(children: [
                                Expanded(child: LinearProgressIndicator(value: total <= 0 ? 0 : (pos / total).clamp(0, 1).toDouble())),
                                const SizedBox(width: 8),
                                Text('${fmtDuration(pos ~/ 1000)} / ${fmtDuration(total ~/ 1000)}', style: const TextStyle(fontSize: 12)),
                              ]);
                            },
                          ),
                        ),
                    ]);
                  },
                )
              : ListTile(
                  leading: _opening == a.id
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_icon(a.kind), color: HsColors.navy),
                  title: Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text([fileSize(a.size), if (a.by != null) a.by!, if (a.at != null) fmtDayTime(a.at)].where((x) => x.isNotEmpty).join(' · ')),
                  onTap: _opening == null ? () => _open(a) : null,
                  onLongPress: a.byUser == me ? () => _delete(a) : null,
                ),
        ),
      if (items != null && items.any((a) => a.byUser == me))
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Press and hold your own file to remove it.', style: TextStyle(color: HsColors.textSecondary, fontSize: 11.5)),
        ),
    ]);
  }
}
