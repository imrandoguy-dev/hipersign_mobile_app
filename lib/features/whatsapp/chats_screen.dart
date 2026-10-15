import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/refresh.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session.dart';
import '../../shared/models/whatsapp.dart';
import '../../shared/widgets/common.dart';
import 'chat_screen.dart';

/// Unread WhatsApp chats, for the badge on the tab (refreshed by the home screen).
final ValueNotifier<int> waUnreadChats = ValueNotifier<int>(0);

/// "12:40 PM" today, "Yesterday", "Mon", else "12 Oct".
String chatTime(DateTime? d, {DateTime? now}) {
  if (d == null) return '';
  final n = now ?? DateTime.now();
  final days = DateTime(n.year, n.month, n.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days == 0) return DateFormat.jm().format(d);
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat('EEE').format(d);
  return DateFormat(d.year == n.year ? 'd MMM' : 'd MMM yyyy').format(d);
}

Future<void> openChat(BuildContext context, {required String phone, String? title}) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(phone: phone, title: title)));

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  Timer? _poll;
  bool _unreadOnly = false;
  List<WaChat> _items = [];
  String? _next;
  bool _loading = false;
  bool _loadingMore = false;
  ApiException? _error;
  DateTime? _syncedAt;

  @override
  void initState() {
    super.initState();
    refreshTick.addListener(_load);
    final cached = context.read<SessionController>().repo.cachedWaChats();
    if (cached != null) _items = cached;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    // New messages show up without pulling down.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    refreshTick.removeListener(_load);
    _debounce?.cancel();
    _poll?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!mounted) return;
    final repo = context.read<SessionController>().repo;
    final query = _q.text.trim();
    if (!quiet) setState(() => _loading = true);
    try {
      final page = await repo.waChats(query: query.isEmpty ? null : query, unreadOnly: _unreadOnly);
      if (!mounted || query != _q.text.trim()) return;
      setState(() {
        _items = page.items;
        _next = page.nextCursor;
        _error = null;
        _syncedAt = DateTime.now();
      });
      if (query.isEmpty && !_unreadOnly) waUnreadChats.value = page.items.where((c) => c.unread > 0).length;
    } on ApiException catch (e) {
      if (mounted && !quiet) setState(() => _error = e);
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (_next == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final q = _q.text.trim();
      final page = await context
          .read<SessionController>()
          .repo
          .waChats(query: q.isEmpty ? null : q, unreadOnly: _unreadOnly, cursor: _next);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _next = page.nextCursor;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _newChat() async {
    final c = TextEditingController();
    final number = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New WhatsApp chat'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone number', hintText: '98765 43210 or +971 50 123 4567'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Open chat')),
        ],
      ),
    );
    if (number == null || number.isEmpty || !mounted) return;
    await openChat(context, phone: number);
    _load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(tooltip: 'New chat', icon: const Icon(Icons.add_comment_outlined), onPressed: _newChat),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) _more();
            return false;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: TextField(
                  controller: _q,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search name or number',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _q.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _q.clear();
                              _load();
                            },
                          ),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 350), _load);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: !_unreadOnly,
                    onSelected: (_) {
                      setState(() => _unreadOnly = false);
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Unread'),
                    selected: _unreadOnly,
                    onSelected: (_) {
                      setState(() => _unreadOnly = true);
                      _load();
                    },
                  ),
                ]),
              ),
              if (_error != null) SyncBanner(error: _error, syncedAt: _syncedAt),
              if (_loading && _items.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
              if (!_loading && _items.isEmpty && _error == null)
                EmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: _unreadOnly ? 'No unread chats' : 'No WhatsApp chats yet',
                  message: _unreadOnly
                      ? 'You have read everything.'
                      : 'When a customer messages your WhatsApp number, the chat appears here.',
                ),
              for (final c in _items)
                ChatTile(
                  chat: c,
                  onTap: () async {
                    await openChat(context, phone: c.phone, title: c.title);
                    _load(quiet: true);
                  },
                ),
              if (_loadingMore) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatTile extends StatelessWidget {
  const ChatTile({super.key, required this.chat, required this.onTap});

  final WaChat chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = chat.unread > 0;
    final initial = chat.title.replaceAll('+', '').trim();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: chat.inErp ? HsColors.cardHigh : HsColors.whatsapp.withValues(alpha: 0.18),
            foregroundColor: HsColors.navy,
            child: chat.inErp && initial.isNotEmpty && !RegExp(r'^\d').hasMatch(initial)
                ? Text(initial[0].toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))
                : const Icon(Icons.person_outline),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15.5, fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Text(chatTime(chat.lastMessageAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: unread ? HsColors.whatsapp : HsColors.textSecondary,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                    )),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                if (chat.lastDirection == 'Outgoing') ...[
                  const Icon(Icons.done_all, size: 15, color: HsColors.textSecondary),
                  const SizedBox(width: 3),
                ],
                Expanded(
                  child: Text(chat.lastMessage ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: unread ? HsColors.textPrimary : HsColors.textSecondary, fontSize: 13.5)),
                ),
                if (unread)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: HsColors.whatsapp, borderRadius: BorderRadius.circular(12)),
                    child: Text('${chat.unread}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                _Tag(chat.partyKind ?? 'New number', strong: !chat.inErp),
                if (chat.ownerName != null) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(chat.ownerName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: HsColors.textSecondary)),
                  ),
                ],
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.strong = false});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: strong ? HsColors.warningBg : HsColors.card,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: strong ? HsColors.warning : HsColors.textSecondary)),
      );
}
