import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../shared/models/models.dart';

/// One audio player per screen; only one recording plays at a time.
class RecordingPlayer extends ChangeNotifier {
  RecordingPlayer() {
    _sub = _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
      }
      notifyListeners();
    });
  }

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _sub;
  String? currentId;
  String? loadingId;

  Stream<Duration> get position => _player.positionStream;
  Duration get duration => _player.duration ?? Duration.zero;
  bool isPlaying(String id) => currentId == id && _player.playing;

  /// Play / pause [id]. [resolvePath] fetches the audio file the first time.
  Future<void> toggle(String id, Future<String> Function() resolvePath) async {
    if (currentId == id && loadingId == null) {
      _player.playing ? await _player.pause() : unawaited(_player.play());
      notifyListeners();
      return;
    }
    await _player.stop();
    currentId = id;
    loadingId = id;
    notifyListeners();
    try {
      final path = await resolvePath();
      if (currentId != id) return; // user tapped another one meanwhile
      await _player.setFilePath(path);
      loadingId = null;
      notifyListeners();
      unawaited(_player.play());
    } catch (e) {
      if (currentId == id) {
        currentId = null;
        loadingId = null;
      }
      notifyListeners();
      showSnack(e is ApiException ? e.message : 'Could not play this recording.', error: true);
    }
  }

  Future<void> seek(Duration d) => _player.seek(d);

  Future<void> stop() async {
    await _player.stop();
    currentId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _player.dispose();
    super.dispose();
  }
}

/// A recording row like a phone's call log: who, when, how long, play button.
/// While playing it shows a seek bar underneath.
class RecordingRow extends StatelessWidget {
  const RecordingRow({
    super.key,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.player,
    this.resolvePath,
    this.status,
    this.statusColor,
    this.trailing,
    this.onLongPress,
    this.onTap,
  });

  final String id;
  final String title;
  final String subtitle;
  final RecordingPlayer player;
  final Future<String> Function()? resolvePath; // null = nothing to play yet
  final String? status;
  final Color? statusColor;
  final Widget? trailing;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final current = player.currentId == id;
        final loading = player.loadingId == id;
        final playing = player.isPlaying(id);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Material(
            color: current ? HsColors.active.withValues(alpha: 0.55) : HsColors.card,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap ?? (resolvePath == null ? null : () => player.toggle(id, resolvePath!)),
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
                child: Column(children: [
                  Row(children: [
                    _PlayButton(
                      enabled: resolvePath != null,
                      loading: loading,
                      playing: playing,
                      onTap: resolvePath == null ? null : () => player.toggle(id, resolvePath!),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, color: HsColors.textSecondary)),
                        if (status != null) ...[
                          const SizedBox(height: 2),
                          Text(status!, style: TextStyle(fontSize: 12, color: statusColor ?? HsColors.textSecondary, fontWeight: FontWeight.w600)),
                        ],
                      ]),
                    ),
                    if (trailing != null) trailing!,
                  ]),
                  if (current && !loading) _SeekBar(player: player),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.enabled, required this.loading, required this.playing, this.onTap});

  final bool enabled;
  final bool loading;
  final bool playing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: playing ? 'Pause' : 'Play',
      child: Material(
        color: enabled ? HsColors.navy : HsColors.cardHigh,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(11),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(
                    enabled ? (playing ? Icons.pause : Icons.play_arrow) : Icons.hourglass_empty,
                    color: enabled ? Colors.white : HsColors.textSecondary,
                    size: enabled ? 24 : 18,
                  ),
          ),
        ),
      ),
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.player});
  final RecordingPlayer player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.position,
      builder: (context, snap) {
        final total = player.duration;
        final pos = snap.data ?? Duration.zero;
        final max = total.inMilliseconds <= 0 ? 1.0 : total.inMilliseconds.toDouble();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Text(fmtDuration(pos.inSeconds), style: const TextStyle(fontSize: 12, color: HsColors.textSecondary)),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  activeTrackColor: HsColors.blue,
                  thumbColor: HsColors.navy,
                  inactiveTrackColor: HsColors.cardHigh,
                ),
                child: Slider(
                  value: pos.inMilliseconds.clamp(0, max.toInt()).toDouble(),
                  max: max,
                  onChanged: (v) => player.seek(Duration(milliseconds: v.round())),
                ),
              ),
            ),
            Text(fmtDuration(total.inSeconds), style: const TextStyle(fontSize: 12, color: HsColors.textSecondary)),
          ]),
        );
      },
    );
  }
}
