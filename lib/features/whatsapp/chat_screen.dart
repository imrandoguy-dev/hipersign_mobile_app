import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/nav.dart';
import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../core/repository.dart';
import '../../shared/models/models.dart';
import '../../shared/models/whatsapp.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/contact_actions.dart';
import '../customers/customer_detail_screen.dart';
import '../recordings/recording_widgets.dart';
import 'chats_screen.dart' show waUnreadChats;
import 'template_sheet.dart';

const _outBubble = Color(0xFFDCF3C8);
const _inBubble = Color(0xFFF2F6FA);
const _readBlue = Color(0xFF34B7F1);

/// One WhatsApp conversation: messages, replies, templates, photos, files and voice messages.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.phone, this.title});

  final String phone;
  final String? title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _player = RecordingPlayer();
  final _recorder = AudioRecorder();
  final Map<String, WaMessage> _byId = {};
  final List<WaMessage> _pending = [];

  WaChat? _chat;
  ApiException? _error;
  bool _loading = true;
  bool _hasMore = false;
  bool _loadingOlder = false;
  bool _sending = false;
  bool _markingRead = false;
  WaMessage? _replyTo;
  Timer? _poll;

  // voice recording
  bool _recording = false;
  DateTime? _recStart;
  Timer? _recTimer;

  Repository get _repo => context.read<SessionController>().repo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _recTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(quiet: true);
  }

  void _onScroll() {
    // The list is reversed: the top (older messages) is the end of the scroll.
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _older();
  }

  List<WaMessage> get _messages {
    final list = _byId.values.toList()..sort((a, b) => (a.at ?? DateTime(0)).compareTo(b.at ?? DateTime(0)));
    return [...list, ..._pending];
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final t = await _repo.waMessages(widget.phone);
      if (!mounted) return;
      setState(() {
        _chat = t.chat;
        for (final m in t.messages) {
          _byId[m.id] = m;
        }
        if (_byId.length <= t.messages.length) _hasMore = t.hasMore;
        _error = null;
      });
      if (t.chat.unread > 0) _markRead();
    } on ApiException catch (e) {
      if (mounted && !quiet) setState(() => _error = e);
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _markRead() async {
    if (_markingRead) return;
    _markingRead = true;
    try {
      await _repo.waMarkRead(widget.phone);
      if (waUnreadChats.value > 0) waUnreadChats.value--;
    } catch (_) {
      // next poll tries again
    } finally {
      _markingRead = false;
    }
  }

  Future<void> _older() async {
    if (!_hasMore || _loadingOlder || _byId.isEmpty) return;
    setState(() => _loadingOlder = true);
    try {
      final oldest = _byId.values.map((m) => m.at).whereType<DateTime>().reduce((a, b) => a.isBefore(b) ? a : b);
      final t = await _repo.waMessages(widget.phone, before: oldest.add(const Duration(seconds: 1)));
      if (!mounted) return;
      setState(() {
        for (final m in t.messages) {
          _byId[m.id] = m;
        }
        _hasMore = t.hasMore;
      });
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  // ------------------------------------------------------------ sending

  void _accept((WaMessage, WaChat) r, WaMessage? placeholder) {
    setState(() {
      if (placeholder != null) _pending.remove(placeholder);
      _byId[r.$1.id] = r.$1;
      _chat = r.$2;
      _replyTo = null;
    });
    bumpRefresh();
  }

  void _failed(WaMessage placeholder, String error) {
    setState(() {
      final i = _pending.indexOf(placeholder);
      if (i >= 0) {
        _pending[i] = WaMessage(
          id: placeholder.id,
          incoming: false,
          kind: placeholder.kind,
          text: placeholder.text,
          localPath: placeholder.localPath,
          media: placeholder.media,
          at: placeholder.at,
          error: error,
        );
      }
    });
  }

  Future<void> _sendText() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    final reply = _replyTo?.waId;
    final placeholder = WaMessage(id: 'local-${DateTime.now().microsecondsSinceEpoch}', incoming: false, kind: 'text', text: text, at: DateTime.now(), pending: true);
    setState(() {
      _sending = true;
      _pending.add(placeholder);
      _text.clear();
    });
    try {
      _accept(await _repo.waSendText(widget.phone, text, replyTo: reply), placeholder);
    } on ApiException catch (e) {
      setState(() {
        _pending.remove(placeholder);
        if (_text.text.isEmpty) _text.text = text; // keep what was typed
      });
      showSnack(e.message, error: true);
      if (e.code == 'VALIDATION_ERROR') _load(quiet: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendFile(String path, String kind, {String? caption}) async {
    final name = path.split('/').last;
    final placeholder = WaMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      incoming: false,
      kind: kind,
      text: caption,
      media: WaMedia(kind: kind, name: name, ext: name.contains('.') ? name.split('.').last.toLowerCase() : null),
      localPath: path,
      at: DateTime.now(),
      pending: true,
    );
    final reply = _replyTo?.waId;
    setState(() => _pending.add(placeholder));
    try {
      _accept(await _repo.waSendMedia(widget.phone, path, caption: caption, replyTo: reply), placeholder);
    } on ApiException catch (e) {
      if (mounted) _failed(placeholder, e.message);
    }
  }

  Future<void> _retry(WaMessage m) async {
    setState(() => _pending.remove(m));
    if (m.localPath != null) {
      await _sendFile(m.localPath!, m.kind, caption: m.text);
    } else if (m.text != null) {
      _text.text = m.text!;
      await _sendText();
    }
  }

  Future<void> _openTemplates() async {
    final r = await showTemplateSheet(context, phone: widget.phone);
    if (r != null && mounted) _accept(r, null);
  }

  // ------------------------------------------------------------ attachments

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Camera'), onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(leading: const Icon(Icons.photo_outlined), title: const Text('Photo from gallery'), onTap: () => Navigator.pop(ctx, 'gallery')),
          ListTile(leading: const Icon(Icons.videocam_outlined), title: const Text('Video'), onTap: () => Navigator.pop(ctx, 'video')),
          ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Document (PDF, Excel...)'), onTap: () => Navigator.pop(ctx, 'document')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      final picker = ImagePicker();
      String? path;
      String kind = 'image';
      switch (choice) {
        case 'camera':
          path = (await picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 2000))?.path;
        case 'gallery':
          path = (await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 2000))?.path;
        case 'video':
          kind = 'video';
          path = (await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 3)))?.path;
        case 'document':
          kind = 'document';
          if (!Platform.isAndroid) {
            showSnack('Documents can be sent from the Android app.', error: true);
            return;
          }
          path = await const MethodChannel('hipersign/phone').invokeMethod<String>('pickDocument');
      }
      if (path == null || !mounted) return;
      final caption = await _confirmFile(path, kind);
      if (caption == null) return;
      await _sendFile(path, kind, caption: caption.isEmpty ? null : caption);
    } on PlatformException catch (e) {
      showSnack(e.message ?? 'Could not open the camera / files.', error: true);
    }
  }

  /// Preview + optional caption. Returns null when cancelled.
  Future<String?> _confirmFile(String path, String kind) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(kind == 'image' ? 'Send photo' : kind == 'video' ? 'Send video' : 'Send document'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (kind == 'image')
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(path), height: 220, fit: BoxFit.cover),
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(kind == 'video' ? Icons.movie_outlined : Icons.insert_drive_file_outlined, size: 32),
                title: Text(path.split('/').last, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(_size(File(path).lengthSync())),
              ),
            const SizedBox(height: 12),
            TextField(controller: c, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'Caption (optional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton.icon(onPressed: () => Navigator.pop(ctx, c.text.trim()), icon: const Icon(Icons.send), label: const Text('Send')),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ voice messages

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        showSnack('Allow the microphone for Hipersign to record voice messages.', error: true);
        return;
      }
      await _player.stop();
      final path = '${Directory.systemTemp.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1),
        path: path,
      );
      HapticFeedback.mediumImpact();
      setState(() {
        _recording = true;
        _recStart = DateTime.now();
      });
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (DateTime.now().difference(_recStart!) >= const Duration(minutes: 5)) _stopRecording(send: true);
      });
    } catch (e) {
      showSnack('Could not start recording.', error: true);
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    _recTimer?.cancel();
    final started = _recStart;
    String? path;
    try {
      path = send ? await _recorder.stop() : null;
      if (!send) await _recorder.cancel();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recStart = null;
    });
    if (!send || path == null) return;
    if (started != null && DateTime.now().difference(started) < const Duration(seconds: 1)) {
      showSnack('Hold on a little longer to record a voice message.');
      return;
    }
    await _sendFile(path, 'audio');
  }

  // ------------------------------------------------------------ UI

  void _onLongPress(WaMessage m) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (m.waId != null && (_chat?.windowOpen ?? false))
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _replyTo = m);
              },
            ),
          if ((m.text ?? m.templateText) != null)
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy text'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: (m.text ?? m.templateText)!));
                Navigator.pop(ctx);
                showSnack('Copied');
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  WaMessage? _quoted(String? waId) {
    if (waId == null) return null;
    for (final m in _byId.values) {
      if (m.waId == waId) return m;
    }
    return null;
  }

  PhoneInfo get _phoneInfo => PhoneInfo(
        raw: widget.phone,
        e164: _chat?.phone ?? widget.phone,
        valid: true,
        telUrl: 'tel:${_chat?.phone ?? widget.phone}',
        whatsappUrl: 'https://wa.me/${(_chat?.phone ?? widget.phone).replaceAll(RegExp(r'\D'), '')}',
      );

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    final title = chat?.title ?? widget.title ?? widget.phone;
    final subtitle = [
      if (chat?.partyKind != null) chat!.partyKind! else if (chat != null) 'Not in ERPNext',
      chat?.phone ?? widget.phone,
    ].join(' · ');
    final messages = _messages.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: chat?.partyId == null ? null : _openParty,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: HsColors.textSecondary)),
          ]),
        ),
        actions: [
          IconButton(tooltip: 'Call', icon: const Icon(Icons.call_outlined), onPressed: () => callPhone(_phoneInfo)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'party') _openParty();
              if (v == 'wa') launchUrl(Uri.parse(_phoneInfo.whatsappUrl!), mode: LaunchMode.externalApplication);
            },
            itemBuilder: (_) => [
              if (chat?.partyId != null) PopupMenuItem(value: 'party', child: Text('Open ${chat!.partyKind?.toLowerCase() ?? 'customer'}')),
              const PopupMenuItem(value: 'wa', child: Text('Open in the WhatsApp app')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (_error != null && _byId.isEmpty)
          Expanded(
            child: Center(
              child: EmptyState(
                icon: Icons.error_outline,
                title: _error!.code == 'NOT_FOUND' ? 'Chat not found' : 'Could not load the chat',
                message: _error!.message,
                action: FilledButton(onPressed: _load, child: const Text('Try again')),
              ),
            ),
          )
        else
          Expanded(
            child: _loading && _byId.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? ListView(children: const [
                        EmptyState(
                          icon: Icons.chat_bubble_outline,
                          title: 'No messages yet',
                          message: 'Start the conversation with an approved template.',
                        ),
                      ])
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        itemCount: messages.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == messages.length) {
                            return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                          }
                          final m = messages[i];
                          final older = i + 1 < messages.length ? messages[i + 1] : null;
                          final newDay = older == null || !_sameDay(older.at, m.at);
                          return Column(children: [
                            if (newDay && m.at != null) _DayChip(m.at!),
                            _Bubble(
                              message: m,
                              repo: _repo,
                              player: _player,
                              quoted: _quoted(m.replyTo),
                              myName: context.read<SessionController>().profile?.fullName,
                              onLongPress: m.pending || m.error != null ? null : () => _onLongPress(m),
                              onRetry: m.error != null ? () => _retry(m) : null,
                            ),
                          ]);
                        },
                      ),
          ),
        _composer(chat),
      ]),
    );
  }

  void _openParty() {
    final c = _chat;
    if (c?.partyId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomerDetailScreen(doctype: c!.partyDoctype!, name: c.partyId!, title: c.partyName ?? c.title)),
    );
  }

  Widget _composer(WaChat? chat) {
    final open = chat?.windowOpen ?? false;
    final closes = chat?.windowClosesAt;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(color: HsColors.background, border: Border(top: BorderSide(color: HsColors.border))),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (chat != null && !open)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: HsColors.warningBg, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.lock_clock_outlined, size: 18, color: HsColors.warning),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'The customer has not written in the last 24 hours. WhatsApp allows only an approved template now - when they reply, you can chat freely.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              ]),
            )
          else if (open && closes != null && closes.difference(DateTime.now()) < const Duration(hours: 3))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('Free replies until ${DateFormat.jm().format(closes)}, after that only templates.',
                  style: const TextStyle(fontSize: 12, color: HsColors.warning)),
            ),
          if (_replyTo != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              decoration: BoxDecoration(
                color: HsColors.card,
                borderRadius: BorderRadius.circular(10),
                border: const Border(left: BorderSide(color: HsColors.whatsapp, width: 3)),
              ),
              child: Row(children: [
                Expanded(child: Text(_summary(_replyTo!), maxLines: 2, overflow: TextOverflow.ellipsis)),
                IconButton(tooltip: 'Cancel reply', icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _replyTo = null)),
              ]),
            ),
          if (_recording)
            Row(children: [
              IconButton(tooltip: 'Delete recording', icon: const Icon(Icons.delete_outline, color: HsColors.danger), onPressed: () => _stopRecording(send: false)),
              const Icon(Icons.fiber_manual_record, color: HsColors.danger, size: 16),
              const SizedBox(width: 6),
              Text('Recording ${fmtDuration(DateTime.now().difference(_recStart ?? DateTime.now()).inSeconds)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              FloatingActionButton.small(
                heroTag: 'wa-send-voice',
                tooltip: 'Send voice message',
                backgroundColor: HsColors.whatsapp,
                foregroundColor: Colors.white,
                onPressed: () => _stopRecording(send: true),
                child: const Icon(Icons.send),
              ),
            ])
          else
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(tooltip: 'Send a template', icon: const Icon(Icons.article_outlined), onPressed: chat == null ? null : _openTemplates),
              if (open) IconButton(tooltip: 'Photo, video or document', icon: const Icon(Icons.attach_file), onPressed: _attach),
              Expanded(
                child: open
                    ? TextField(
                        controller: _text,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          isDense: true,
                          filled: true,
                          fillColor: HsColors.card,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: chat == null ? null : _openTemplates,
                        icon: const Icon(Icons.article_outlined),
                        label: const Text('Send a template'),
                      ),
              ),
              const SizedBox(width: 6),
              if (open)
                FloatingActionButton.small(
                  heroTag: 'wa-send',
                  tooltip: _text.text.trim().isEmpty ? 'Record a voice message' : 'Send',
                  backgroundColor: HsColors.whatsapp,
                  foregroundColor: Colors.white,
                  onPressed: _text.text.trim().isEmpty ? _startRecording : (_sending ? null : _sendText),
                  child: Icon(_text.text.trim().isEmpty ? Icons.mic : Icons.send),
                ),
            ]),
        ]),
      ),
    );
  }
}

bool _sameDay(DateTime? a, DateTime? b) =>
    a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;

String _size(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

String _summary(WaMessage m) {
  if (m.text != null) return m.text!;
  if (m.templateText != null) return m.templateText!;
  return switch (m.kind) {
    'image' => '📷 Photo',
    'audio' => '🎤 Voice message',
    'video' => '🎬 Video',
    'document' => '📄 ${m.media?.name ?? 'Document'}',
    _ => m.kind,
  };
}

class _DayChip extends StatelessWidget {
  const _DayChip(this.day);
  final DateTime day;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: HsColors.cardHigh, borderRadius: BorderRadius.circular(10)),
          child: Text(relativeDay(day), style: const TextStyle(fontSize: 12, color: HsColors.textSecondary)),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.repo,
    required this.player,
    this.quoted,
    this.myName,
    this.onLongPress,
    this.onRetry,
  });

  final WaMessage message;
  final Repository repo;
  final RecordingPlayer player;
  final WaMessage? quoted;
  final String? myName;
  final VoidCallback? onLongPress;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.kind == 'reaction') {
      return Align(
        alignment: m.incoming ? Alignment.centerLeft : Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: Text('${m.incoming ? 'Reacted' : 'You reacted'} ${m.text ?? ''}',
              style: const TextStyle(fontSize: 12.5, color: HsColors.textSecondary)),
        ),
      );
    }
    final out = !m.incoming;
    final width = MediaQuery.sizeOf(context).width * 0.78;
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(maxWidth: width),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
          decoration: BoxDecoration(
            color: out ? _outBubble : _inBubble,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(out ? 14 : 4),
              bottomRight: Radius.circular(out ? 4 : 14),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (out && m.by != null && m.by != myName)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(m.by!, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: HsColors.blue)),
              ),
            if (quoted != null)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: const Border(left: BorderSide(color: HsColors.whatsapp, width: 3)),
                ),
                child: Text(_summary(quoted!), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
              ),
            ..._content(context),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(m.at == null ? '' : DateFormat.jm().format(m.at!), style: const TextStyle(fontSize: 11, color: HsColors.textSecondary)),
              if (out) ...[const SizedBox(width: 4), _ticks()],
            ]),
            if (m.error != null)
              InkWell(
                onTap: onRetry,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Not sent: ${m.error}  ·  Tap to retry',
                      style: const TextStyle(fontSize: 12, color: HsColors.danger, fontWeight: FontWeight.w600)),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _ticks() {
    final m = message;
    if (m.error != null) return const Icon(Icons.error_outline, size: 15, color: HsColors.danger);
    if (m.pending) return const Icon(Icons.schedule, size: 14, color: HsColors.textSecondary);
    return switch (m.status) {
      'read' => const Icon(Icons.done_all, size: 16, color: _readBlue),
      'delivered' => const Icon(Icons.done_all, size: 16, color: HsColors.textSecondary),
      'failed' => const Icon(Icons.error_outline, size: 15, color: HsColors.danger),
      _ => const Icon(Icons.done, size: 16, color: HsColors.textSecondary),
    };
  }

  List<Widget> _content(BuildContext context) {
    final m = message;
    final widgets = <Widget>[];
    if (m.kind == 'template') {
      widgets.add(Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.article_outlined, size: 14, color: HsColors.textSecondary),
        const SizedBox(width: 4),
        Flexible(
          child: Text('Template · ${m.template ?? ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: HsColors.textSecondary)),
        ),
      ]));
      widgets.add(const SizedBox(height: 4));
    }
    final media = m.media;
    if (media != null) {
      switch (media.kind) {
        case 'image':
          widgets.add(_ImageView(message: m, repo: repo));
        case 'audio':
          widgets.add(_VoiceView(message: m, repo: repo, player: player));
        default:
          widgets.add(_FileView(message: m, repo: repo));
      }
      widgets.add(const SizedBox(height: 4));
    }
    final text = m.kind == 'template' ? (m.templateText ?? m.text) : m.text;
    if (text != null && text.isNotEmpty) {
      widgets.add(Text(text, style: const TextStyle(fontSize: 15, height: 1.3)));
    } else if (media == null && m.kind != 'template' && m.kind != 'text') {
      widgets.add(Text('[${m.kind}]', style: const TextStyle(fontStyle: FontStyle.italic, color: HsColors.textSecondary)));
    }
    return widgets;
  }
}

Future<String> _fileOf(WaMessage m, Repository repo) async => m.localPath ?? await repo.waMediaFile(m);

class _ImageView extends StatefulWidget {
  const _ImageView({required this.message, required this.repo});
  final WaMessage message;
  final Repository repo;

  @override
  State<_ImageView> createState() => _ImageViewState();
}

class _ImageViewState extends State<_ImageView> {
  late final Future<String> _path = _fileOf(widget.message, widget.repo);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _path,
      builder: (context, snap) {
        if (snap.hasError) {
          return const SizedBox(height: 60, child: Center(child: Text('Photo not available', style: TextStyle(color: HsColors.textSecondary))));
        }
        if (!snap.hasData) {
          return const SizedBox(width: 200, height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
                body: Center(child: InteractiveViewer(child: Image.file(File(snap.data!)))),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(children: [
              Image.file(File(snap.data!), height: 220, fit: BoxFit.cover),
              if (widget.message.pending)
                const Positioned.fill(child: ColoredBox(color: Colors.black26, child: Center(child: CircularProgressIndicator()))),
            ]),
          ),
        );
      },
    );
  }
}

class _VoiceView extends StatelessWidget {
  const _VoiceView({required this.message, required this.repo, required this.player});
  final WaMessage message;
  final Repository repo;
  final RecordingPlayer player;

  @override
  Widget build(BuildContext context) {
    final id = message.id;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final current = player.currentId == id;
        final loading = player.loadingId == id;
        final playing = player.isPlaying(id);
        return SizedBox(
          width: 230,
          child: Row(children: [
            IconButton(
              tooltip: playing ? 'Pause' : 'Play',
              onPressed: message.pending ? null : () => player.toggle(id, () => _fileOf(message, repo)),
              icon: loading || message.pending
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 36, color: HsColors.navy),
            ),
            Expanded(
              child: current && !loading
                  ? StreamBuilder<Duration>(
                      stream: player.position,
                      builder: (context, snap) {
                        final total = player.duration.inMilliseconds;
                        final pos = (snap.data ?? Duration.zero).inMilliseconds;
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          LinearProgressIndicator(value: total <= 0 ? 0 : (pos / total).clamp(0, 1).toDouble(), minHeight: 3),
                          const SizedBox(height: 4),
                          Text('${fmtDuration(pos ~/ 1000)} / ${fmtDuration(total ~/ 1000)}', style: const TextStyle(fontSize: 11.5)),
                        ]);
                      },
                    )
                  : const Row(children: [
                      Icon(Icons.mic, size: 16, color: HsColors.textSecondary),
                      SizedBox(width: 4),
                      Text('Voice message', style: TextStyle(fontSize: 13)),
                    ]),
            ),
          ]),
        );
      },
    );
  }
}

class _FileView extends StatefulWidget {
  const _FileView({required this.message, required this.repo});
  final WaMessage message;
  final Repository repo;

  @override
  State<_FileView> createState() => _FileViewState();
}

class _FileViewState extends State<_FileView> {
  bool _opening = false;

  Future<void> _open() async {
    setState(() => _opening = true);
    try {
      final path = await _fileOf(widget.message, widget.repo);
      final r = await OpenFilex.open(path);
      if (r.type != ResultType.done) showSnack('No app on this phone can open this file.', error: true);
    } on ApiException catch (e) {
      showSnack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.message.media!;
    final video = media.kind == 'video';
    return InkWell(
      onTap: widget.message.pending || _opening ? null : _open,
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          _opening || widget.message.pending
              ? const SizedBox(width: 30, height: 30, child: Padding(padding: EdgeInsets.all(5), child: CircularProgressIndicator(strokeWidth: 2)))
              : Icon(video ? Icons.play_circle_outline : Icons.insert_drive_file_outlined, size: 30, color: HsColors.navy),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              video ? 'Video' : (media.name ?? 'Document'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    );
  }
}
