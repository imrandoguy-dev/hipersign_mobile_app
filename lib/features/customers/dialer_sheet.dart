import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/auth/session.dart';
import '../../shared/models/models.dart';
import 'customer_detail_screen.dart';

/// Small phone-style keypad: type a number, then Call or WhatsApp.
/// While typing, it looks the number up in ERPNext and shows who it belongs to.
Future<void> openDialer(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: HsColors.background,
      builder: (_) => const _DialerSheet(),
    );

/// Digits the user typed, keeping a leading +.
String _clean(String s) {
  final plus = s.trimLeft().startsWith('+');
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  return plus ? '+$digits' : digits;
}

/// WhatsApp needs the full international number. Default country is India (+91).
String _whatsappNumber(String typed) {
  final n = _clean(typed);
  if (n.startsWith('+')) return n.substring(1);
  if (n.startsWith('00')) return n.substring(2);
  if (n.length == 11 && n.startsWith('0')) return '91${n.substring(1)}';
  if (n.length == 10) return '91$n';
  return n;
}

class _DialerSheet extends StatefulWidget {
  const _DialerSheet();

  @override
  State<_DialerSheet> createState() => _DialerSheetState();
}

class _DialerSheetState extends State<_DialerSheet> {
  String _number = '';
  Timer? _debounce;
  List<Party> _matches = [];
  bool _looking = false;
  int _lookupSeq = 0;

  bool get _usable => _clean(_number).replaceAll('+', '').length >= 7;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _set(String value) {
    setState(() => _number = value);
    _debounce?.cancel();
    final digits = _clean(value).replaceAll('+', '');
    if (digits.length < 5) {
      setState(() {
        _matches = [];
        _looking = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _lookup(digits));
  }

  Future<void> _lookup(String digits) async {
    final seq = ++_lookupSeq;
    setState(() => _looking = true);
    try {
      // Search by the last 10 digits so "+91 98470 12345" and "098470 12345" both match.
      final q = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
      final page = await context.read<SessionController>().repo.searchParties(q, 'all');
      if (!mounted || seq != _lookupSeq) return;
      setState(() => _matches = page.items.take(3).toList());
    } catch (_) {
      if (mounted && seq == _lookupSeq) setState(() => _matches = []);
    } finally {
      if (mounted && seq == _lookupSeq) setState(() => _looking = false);
    }
  }

  void _press(String key) {
    HapticFeedback.selectionClick();
    _set(_number + key);
  }

  void _backspace() {
    if (_number.isEmpty) return;
    HapticFeedback.selectionClick();
    _set(_number.substring(0, _number.length - 1));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || _clean(text).replaceAll('+', '').isEmpty) return;
    _set(_clean(text));
  }

  Future<void> _call() async {
    if (!_usable) return;
    final ok = await launchUrl(Uri.parse('tel:${_clean(_number)}'));
    if (!ok) showSnack('Could not open the phone dialer.', error: true);
  }

  Future<void> _whatsApp() async {
    if (!_usable) return;
    final ok = await launchUrl(Uri.parse('https://wa.me/${_whatsappNumber(_number)}'), mode: LaunchMode.externalApplication);
    if (!ok) showSnack('Could not open WhatsApp.', error: true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Number display
          GestureDetector(
            onLongPress: _paste,
            child: SizedBox(
              height: 52,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _number.isEmpty ? 'Enter number' : _number,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: _number.isEmpty ? HsColors.textSecondary.withValues(alpha: 0.6) : HsColors.navy,
                    ),
                  ),
                ),
              ),
            ),
          ),
          _MatchLine(matches: _matches, looking: _looking, typed: _number),
          const SizedBox(height: 8),
          // Keypad
          for (final row in const [
            [('1', ''), ('2', 'ABC'), ('3', 'DEF')],
            [('4', 'GHI'), ('5', 'JKL'), ('6', 'MNO')],
            [('7', 'PQRS'), ('8', 'TUV'), ('9', 'WXYZ')],
            [('*', ''), ('0', '+'), ('#', '')],
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                for (final k in row)
                  _Key(
                    digit: k.$1,
                    letters: k.$2,
                    onTap: () => _press(k.$1),
                    onLongPress: k.$1 == '0' ? () => _press('+') : null,
                  ),
              ]),
            ),
          const SizedBox(height: 10),
          // WhatsApp · Call · Backspace
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _Action(
              tooltip: 'WhatsApp',
              icon: Icons.chat,
              color: HsColors.whatsapp,
              filled: false,
              enabled: _usable,
              onTap: _whatsApp,
            ),
            _Action(
              tooltip: 'Call',
              icon: Icons.call,
              color: const Color(0xFF1FA855),
              filled: true,
              enabled: _usable,
              onTap: _call,
            ),
            SizedBox(
              width: 64,
              height: 64,
              child: _number.isEmpty
                  ? null
                  : Tooltip(
                      message: 'Delete (hold to clear)',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _backspace,
                        onLongPress: () => _set(''),
                        child: const Icon(Icons.backspace_outlined, color: HsColors.textSecondary, size: 26),
                      ),
                    ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _MatchLine extends StatelessWidget {
  const _MatchLine({required this.matches, required this.looking, required this.typed});

  final List<Party> matches;
  final bool looking;
  final String typed;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (matches.isNotEmpty) {
      final p = matches.first;
      child = InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CustomerDetailScreen(doctype: p.doctype, name: p.id, title: p.name)),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: HsColors.active, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.person, size: 16, color: HsColors.onPastel),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${p.name} · ${p.kind}${matches.length > 1 ? '  +${matches.length - 1} more' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: HsColors.onPastel, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: HsColors.onPastel),
          ]),
        ),
      );
    } else if (looking) {
      child = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
    } else {
      child = const SizedBox.shrink();
    }
    return SizedBox(height: 34, child: Center(child: child));
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.digit, required this.letters, required this.onTap, this.onLongPress});

  final String digit;
  final String letters;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: digit,
      child: Material(
        color: HsColors.card,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox(
            width: 72,
            height: 72,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(digit, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500, color: HsColors.textPrimary, height: 1.1)),
              if (letters.isNotEmpty)
                Text(letters,
                    style: const TextStyle(fontSize: 10, letterSpacing: 1.5, color: HsColors.textSecondary, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.filled,
    required this.enabled,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final bool filled;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = enabled ? color : color.withValues(alpha: 0.35);
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: filled ? c : HsColors.card,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(icon, size: 28, color: filled ? Colors.white : c),
            ),
          ),
        ),
      ),
    );
  }
}
