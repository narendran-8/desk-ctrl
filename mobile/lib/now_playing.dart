import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class NowPlaying {
  const NowPlaying({
    this.title = '',
    this.app = '',
    this.playing = false,
    this.icon,
    this.positionMs = -1,
    this.durationMs = 0,
    this.rate = 1,
    this.canSeek = false,
    this.seekKey = '',
    this.receivedAt,
  });
  final String title, app;
  final bool playing;
  final Uint8List? icon;
  final int positionMs, durationMs;
  final double rate;
  final bool canSeek;
  final String seekKey;
  final DateTime? receivedAt;
  bool get hasTimeline => positionMs >= 0 || durationMs > 0;
  bool get seekable =>
      canSeek &&
      positionMs >= 0 &&
      durationMs > 0 &&
      RegExp(r'^[0-9a-f]{16}$').hasMatch(seekKey);
  int positionAt(DateTime now) {
    final elapsed = playing && receivedAt != null
        ? now.difference(receivedAt!).inMilliseconds.clamp(0, 4000) * rate
        : 0;
    return (positionMs.clamp(0, 1 << 52) + elapsed).round().clamp(
      0,
      durationMs > 0 ? durationMs : 1 << 52,
    );
  }

  factory NowPlaying.fromJson(Map<String, dynamic> json) {
    Uint8List? icon;
    try {
      final encoded = json['icon'];
      if (encoded is String && encoded.length <= 16000 && encoded.isNotEmpty) {
        icon = base64Decode(encoded);
      }
    } catch (_) {}
    return NowPlaying(
      title: json['title'] is String ? json['title'] as String : '',
      app: json['app'] is String ? json['app'] as String : '',
      playing: json['playing'] == true,
      icon: icon,
      positionMs: json['positionMs'] is num
          ? (json['positionMs'] as num).toInt()
          : -1,
      durationMs: json['durationMs'] is num
          ? (json['durationMs'] as num).toInt().clamp(0, 1 << 52)
          : 0,
      rate: json['rate'] is num && (json['rate'] as num).isFinite
          ? (json['rate'] as num).toDouble()
          : 1,
      canSeek: json['canSeek'] == true,
      seekKey: json['seekKey'] is String ? json['seekKey'] as String : '',
      receivedAt: DateTime.now(),
    );
  }
}

/// Display-only: parent trackpad gestures continue to work normally.
class NowPlayingBadge extends StatelessWidget {
  const NowPlayingBadge({super.key, required this.media});
  final NowPlaying media;

  @override
  Widget build(BuildContext context) {
    if (media.title.isEmpty) return const SizedBox.shrink();
    return Semantics(
      label: '${media.app}: ${media.title}',
      child: SizedBox(
        key: const Key('nowPlayingBadge'),
        height: 24,
        child: LayoutBuilder(
          builder: (context, box) {
            final measure = TextPainter(
              text: TextSpan(text: media.title, style: _titleStyle),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            )..layout();
            final titleWidth = measure.width.clamp(
              0.0,
              (box.maxWidth - 22).clamp(0.0, double.infinity),
            );
            measure.dispose();
            return Center(
              child: Row(
                key: const Key('nowPlayingContent'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (media.icon != null)
                    Image.memory(
                      media.icon!,
                      width: 16,
                      height: 16,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.music_note,
                        size: 16,
                        color: Colors.white54,
                      ),
                    )
                  else
                    const Icon(
                      Icons.music_note,
                      size: 16,
                      color: Colors.white54,
                    ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: titleWidth,
                    height: 20,
                    child: _TrackTitle(
                      key: ValueKey('${media.app}:${media.title}'),
                      title: media.title,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

const _titleStyle = TextStyle(color: Colors.white60, fontSize: 12);

class _TrackTitle extends StatefulWidget {
  const _TrackTitle({super.key, required this.title});
  final String title;
  @override
  State<_TrackTitle> createState() => _TrackTitleState();
}

class _TrackTitleState extends State<_TrackTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scroll = AnimationController(vsync: this);
  static const style = _titleStyle;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final text = TextPainter(
        text: TextSpan(text: widget.title, style: style),
        textDirection: Directionality.of(context),
        maxLines: 1,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = text.width;
      text.dispose();
      if (width <= box.maxWidth || MediaQuery.disableAnimationsOf(context)) {
        if (_scroll.isAnimating) _scroll.stop();
        return Text(
          widget.title,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.clip,
          textAlign: TextAlign.center,
        );
      }
      final distance = width + 24;
      _scroll.duration = Duration(
        milliseconds: (distance / 18 * 1000).round() + 1200,
      );
      if (!_scroll.isAnimating) _scroll.repeat();
      return ClipRect(
        child: AnimatedBuilder(
          animation: _scroll,
          builder: (context, _) {
            final total = _scroll.duration!.inMilliseconds.toDouble();
            final progress = ((_scroll.value * total - 1200) / (total - 1200))
                .clamp(0.0, 1.0);
            return OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Transform.translate(
                offset: Offset(-distance * progress, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.title, style: style, maxLines: 1),
                    const SizedBox(width: 24),
                    Text(widget.title, style: style, maxLines: 1),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

String playbackTime(int milliseconds) {
  final seconds = milliseconds.clamp(0, 1 << 52) ~/ 1000;
  final h = seconds ~/ 3600;
  final m = seconds ~/ 60 % 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:$s'
      : '${seconds ~/ 60}:$s';
}

/// A sibling of the raw pointer surface so seeking never moves/clicks the PC mouse.
class MediaTimeline extends StatefulWidget {
  const MediaTimeline({
    super.key,
    required this.media,
    required this.onSeek,
    this.onAction,
  });
  final NowPlaying media;
  final void Function(String trackKey, int positionMs) onSeek;
  final void Function(String action)? onAction;
  @override
  State<MediaTimeline> createState() => _MediaTimelineState();
}

class _MediaTimelineState extends State<MediaTimeline> {
  Timer? _clock, _pendingTimer;
  double? _drag, _pending;
  String? _dragKey;
  @override
  void initState() {
    super.initState();
    _syncClock();
  }

  void _syncClock() {
    _clock?.cancel();
    if (widget.media.playing && widget.media.positionMs >= 0) {
      _clock = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(MediaTimeline old) {
    super.didUpdateWidget(old);
    if (old.media.seekKey != widget.media.seekKey) {
      _drag = _pending = null;
      _dragKey = null;
      _pendingTimer?.cancel();
    } else if (_pending != null &&
        (widget.media.positionMs - _pending!).abs() < 1500) {
      _pending = null;
      _pendingTimer?.cancel();
    }
    _syncClock();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pendingTimer?.cancel();
    super.dispose();
  }

  Widget _control(
    String key,
    IconData icon,
    String label,
    VoidCallback? action,
  ) => Center(
    child: SizedBox(
      width: 28,
      height: 28,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: const CircleBorder(),
        child: IconButton(
          key: Key(key),
          tooltip: label,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          icon: Icon(icon, size: 19),
          onPressed: action,
        ),
      ),
    ),
  );

  void _step(int delta) {
    final m = widget.media;
    if (!m.seekable) return;
    final current = _pending ?? m.positionAt(DateTime.now()).toDouble();
    final target = (current + delta).clamp(0, m.durationMs).round();
    setState(() => _pending = target.toDouble());
    widget.onSeek(m.seekKey, target);
    _pendingTimer?.cancel();
    _pendingTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _pending = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.media;
    final position =
        (_drag ?? _pending ?? m.positionAt(DateTime.now()).toDouble()).clamp(
          0.0,
          m.durationMs > 0 ? m.durationMs.toDouble() : double.infinity,
        );
    return SizedBox(
      key: const Key('mediaTimeline'),
      height: 56,
      child: Stack(
        children: [
          SizedBox(
            height: 40,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: Colors.red,
                inactiveTrackColor: Colors.grey.shade700,
                thumbColor: Colors.red,
                disabledActiveTrackColor: Colors.red,
                disabledInactiveTrackColor: Colors.grey.shade700,
                disabledThumbColor: Colors.red,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                key: const Key('mediaSeekBar'),
                allowedInteraction: SliderInteraction.tapAndSlide,
                min: 0,
                max: m.durationMs > 0 ? m.durationMs.toDouble() : 1,
                value: m.durationMs > 0 ? position : 0,
                label: playbackTime(position.round()),
                onChangeStart: m.seekable
                    ? (value) {
                        _dragKey = m.seekKey;
                        setState(() => _drag = value);
                      }
                    : null,
                onChanged: m.seekable
                    ? (value) => setState(() => _drag = value)
                    : null,
                onChangeEnd: m.seekable
                    ? (value) {
                        final key = _dragKey;
                        _dragKey = null;
                        if (key != m.seekKey) {
                          setState(() => _drag = null);
                          return;
                        }
                        setState(() {
                          _drag = null;
                          _pending = value;
                        });
                        widget.onSeek(key!, value.round());
                        _pendingTimer?.cancel();
                        _pendingTimer = Timer(const Duration(seconds: 2), () {
                          if (mounted) setState(() => _pending = null);
                        });
                      }
                    : null,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _control(
                  'mediaPrevious',
                  Icons.skip_previous,
                  'Previous track',
                  widget.onAction == null
                      ? null
                      : () => widget.onAction!('previous'),
                ),
                _control(
                  'mediaBackward',
                  Icons.fast_rewind,
                  'Back 10 seconds',
                  m.seekable ? () => _step(-10000) : null,
                ),
                _control(
                  'mediaPlayPause',
                  m.playing ? Icons.pause : Icons.play_arrow,
                  m.playing ? 'Pause' : 'Play',
                  widget.onAction == null
                      ? null
                      : () => widget.onAction!('playPause'),
                ),
                _control(
                  'mediaForward',
                  Icons.fast_forward,
                  'Forward 10 seconds',
                  m.seekable ? () => _step(10000) : null,
                ),
                _control(
                  'mediaNext',
                  Icons.skip_next,
                  'Next track',
                  widget.onAction == null
                      ? null
                      : () => widget.onAction!('next'),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 40,
            height: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  m.positionMs >= 0 ? playbackTime(position.round()) : '--:--',
                  key: const Key('mediaElapsed'),
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
                Text(
                  m.durationMs > 0 ? playbackTime(m.durationMs) : 'LIVE',
                  key: const Key('mediaDuration'),
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
