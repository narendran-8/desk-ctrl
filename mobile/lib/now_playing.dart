import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'split_media_seek_bar.dart';

class NowPlaying {
  const NowPlaying({
    this.title = '',
    this.app = '',
    this.player = '',
    this.trackId = '',
    this.mediaUrl = '',
    this.playing = false,
    this.icon,
    this.positionMs = -1,
    this.durationMs = 0,
    this.rate = 1,
    this.canSeek = false,
    this.seekKey = '',
    this.receivedAt,
    this.positionEstimated = false,
  });
  final String title, app, player, trackId, mediaUrl;
  final bool playing;
  final Uint8List? icon;
  final int positionMs, durationMs;
  final double rate;
  final bool canSeek;
  final String seekKey;
  final DateTime? receivedAt;
  final bool positionEstimated;

  NowPlaying afterSeek(int target, {DateTime? now}) => NowPlaying(
    title: title,
    app: app,
    player: player,
    trackId: trackId,
    mediaUrl: mediaUrl,
    playing: playing,
    icon: icon,
    positionMs: target,
    durationMs: durationMs,
    rate: rate,
    canSeek: canSeek,
    seekKey: seekKey,
    receivedAt: now ?? DateTime.now(),
    positionEstimated: true,
  );
  String get identity => player.isNotEmpty && trackId.isNotEmpty
      ? '$player\u0000$trackId\u0000$title\u0000$mediaUrl'
      : '$app\u0000$title\u0000$seekKey';
  bool sameTrack(NowPlaying other) =>
      title.isNotEmpty &&
      title == other.title &&
      app == other.app &&
      identity == other.identity;
  bool get hasTimeline => positionMs >= 0 || durationMs > 0;
  bool get canStep =>
      canSeek && positionMs >= 0 && RegExp(r'^[0-9a-f]{16}$').hasMatch(seekKey);
  bool get seekable => canStep && durationMs > 0;
  int positionAt(DateTime now) {
    final elapsed = playing && receivedAt != null
        ? now.difference(receivedAt!).inMilliseconds.clamp(0, 4000) * rate
        : 0;
    return (positionMs.clamp(0, 1 << 52) + elapsed).round().clamp(
      0,
      durationMs > 0 ? durationMs : 1 << 52,
    );
  }

  factory NowPlaying.fromJson(
    Map<String, dynamic> json, {
    NowPlaying? previous,
    DateTime? now,
  }) {
    Uint8List? icon;
    try {
      final encoded = json['icon'];
      if (encoded is String && encoded.length <= 16000 && encoded.isNotEmpty) {
        icon = base64Decode(encoded);
      }
    } catch (_) {}
    final current = NowPlaying(
      title: json['title'] is String ? json['title'] as String : '',
      app: json['app'] is String ? json['app'] as String : '',
      player: json['player'] is String ? json['player'] as String : '',
      trackId: json['trackId'] is String ? json['trackId'] as String : '',
      mediaUrl: json['mediaUrl'] is String ? json['mediaUrl'] as String : '',
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
      receivedAt: now ?? DateTime.now(),
    );
    if (previous == null || !current.sameTrack(previous)) return current;
    final expected = previous.positionAt(current.receivedAt!);
    final raw = current.positionMs;
    // A seek preview must not expire into an unchanged pre-seek sample or a
    // browser's buffering zero. Once genuine feedback resumes, use it again.
    final confirmed = raw >= 0 && (raw - expected).abs() < 3000;
    final estimating = previous.positionEstimated && !confirmed;
    // Browsers can omit timing fields while buffering after SetPosition.
    // Never borrow timing from a different player/video or from an empty report.
    return NowPlaying(
      title: current.title,
      app: current.app,
      player: current.player,
      trackId: current.trackId,
      mediaUrl: current.mediaUrl,
      playing: current.playing,
      icon: current.icon,
      positionMs: estimating
          ? expected
          : current.positionMs >= 0
          ? current.positionMs
          : previous.positionMs >= 0
          ? previous.positionAt(current.receivedAt!)
          : -1,
      durationMs: current.durationMs > 0
          ? current.durationMs
          : previous.durationMs,
      rate: current.rate,
      canSeek: current.canSeek,
      seekKey: current.seekKey,
      receivedAt: current.receivedAt,
      positionEstimated: estimating,
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
    this.onControl,
  });
  final NowPlaying media;
  final void Function(String trackKey, int positionMs) onSeek;
  final void Function(int hid)? onControl;
  @override
  State<MediaTimeline> createState() => _MediaTimelineState();
}

class _MediaTimelineState extends State<MediaTimeline> {
  Timer? _clock, _pendingTimer;
  double? _drag, _pending;
  String? _dragKey;
  double _titleSwipe = 0;
  String? _titleIdentity;
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
    if (old.media.identity != widget.media.identity) {
      _drag = _pending = null;
      _dragKey = null;
      _titleIdentity = null;
      _pendingTimer?.cancel();
    } else if (_dragKey != null && old.media.seekKey != widget.media.seekKey) {
      _dragKey = widget.media.seekKey;
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

  void _skip(int delta) {
    final m = widget.media;
    if (!m.canStep) return;
    final base = _pending ?? m.positionAt(DateTime.now()).toDouble();
    final target = (base.round() + delta).clamp(
      0,
      m.durationMs > 0 ? m.durationMs : 1 << 52,
    );
    if (target == base.round()) return;
    setState(() => _pending = target.toDouble());
    widget.onSeek(m.seekKey, target);
    _pendingTimer?.cancel();
    _pendingTimer = Timer(const Duration(seconds: 5), () {
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
    Widget button(String name, IconData icon, VoidCallback? action) => SizedBox(
      width: 26,
      height: 40,
      child: IconButton(
        key: Key(name),
        padding: EdgeInsets.zero,
        iconSize: 18,
        color: Colors.white60,
        onPressed: action,
        icon: Icon(icon),
      ),
    );

    Widget time(String value, String key) => SizedBox(
      width: 44,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          key: Key(key),
          style: const TextStyle(color: Colors.white60, fontSize: 10),
        ),
      ),
    );
    return SizedBox(
      key: const Key('mediaTimeline'),
      height: 64,
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                button(
                  'mediaPrevious',
                  Icons.skip_previous,
                  widget.onControl == null
                      ? null
                      : () => widget.onControl!(0x80B6),
                ),

                time(
                  m.positionMs >= 0
                      ? '${m.positionEstimated ? '~' : ''}${playbackTime(position.round())}'
                      : '--:--',
                  'mediaElapsed',
                ),
                Expanded(
                  child: SplitMediaSeekBar(
                    key: const Key('mediaSeekBar'),
                    max: m.durationMs > 0 ? m.durationMs.toDouble() : 1,
                    value: m.durationMs > 0 ? position : 0,
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
                            _pendingTimer = Timer(
                              const Duration(seconds: 5),
                              () {
                                if (mounted) setState(() => _pending = null);
                              },
                            );
                          }
                        : null,

                    onCancel: () => setState(() {
                      _drag = null;
                      _dragKey = null;
                    }),
                    center: SizedBox(
                      width: 30,
                      height: 30,
                      child: Material(
                        color: const Color(0xFF151A20),
                        shape: const CircleBorder(),
                        child: IconButton(
                          key: const Key('mediaPlayPause'),
                          padding: EdgeInsets.zero,
                          iconSize: 22,
                          color: Colors.white70,
                          onPressed: widget.onControl == null
                              ? null
                              : () => widget.onControl!(0x80CD),
                          icon: Icon(
                            m.playing ? Icons.pause : Icons.play_arrow,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                time(
                  m.durationMs > 0 ? playbackTime(m.durationMs) : '--:--',
                  'mediaDuration',
                ),

                button(
                  'mediaNext',
                  Icons.skip_next,
                  widget.onControl == null
                      ? null
                      : () => widget.onControl!(0x80B5),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 24,
            child: Row(
              children: [
                _SeekRepeatButton(
                  key: ValueKey('mediaBackward:${m.identity}'),
                  name: 'mediaBackward',
                  icon: Icons.fast_rewind,
                  onStep: m.canStep ? () => _skip(-10000) : null,
                ),
                Expanded(
                  child: GestureDetector(
                    key: const Key('mediaTrackSwipe'),
                    dragStartBehavior: DragStartBehavior.down,
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: m.canStep
                        ? (_) {
                            _titleSwipe = 0;
                            _titleIdentity = m.identity;
                          }
                        : null,
                    onHorizontalDragUpdate: m.canStep
                        ? (event) => _titleSwipe += event.delta.dx
                        : null,
                    onHorizontalDragCancel: () => _titleIdentity = null,
                    onHorizontalDragEnd: m.canStep
                        ? (_) {
                            final sameTrack =
                                _titleIdentity == widget.media.identity;
                            _titleIdentity = null;
                            if (sameTrack && _titleSwipe.abs() >= 24) {
                              _skip(_titleSwipe > 0 ? 10000 : -10000);
                            }
                          }
                        : null,
                    child: NowPlayingBadge(media: m),
                  ),
                ),
                _SeekRepeatButton(
                  key: ValueKey('mediaForward:${m.identity}'),
                  name: 'mediaForward',
                  icon: Icons.fast_forward,
                  onStep: m.canStep ? () => _skip(10000) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A tap seeks once; holding repeats until release, cancellation or removal.
class _SeekRepeatButton extends StatefulWidget {
  const _SeekRepeatButton({
    super.key,
    required this.name,
    required this.icon,
    required this.onStep,
  });
  final String name;
  final IconData icon;
  final VoidCallback? onStep;
  @override
  State<_SeekRepeatButton> createState() => _SeekRepeatButtonState();
}

class _SeekRepeatButtonState extends State<_SeekRepeatButton> {
  Timer? _repeat;
  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void didUpdateWidget(_SeekRepeatButton old) {
    super.didUpdateWidget(old);
    if (widget.onStep == null) _stop();
  }

  @override
  void deactivate() {
    _stop();
    super.deactivate();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.onStep != null,
    label: widget.name == 'mediaForward' ? 'Seek forward' : 'Seek backward',
    onTap: widget.onStep,
    child: GestureDetector(
      key: Key(widget.name),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onStep,
      onLongPressStart: widget.onStep == null
          ? null
          : (_) {
              _stop();
              widget.onStep!();
              _repeat = Timer.periodic(
                const Duration(milliseconds: 250),
                (_) => widget.onStep?.call(),
              );
            },
      onLongPressEnd: (_) => _stop(),
      onLongPressCancel: _stop,
      onLongPressMoveUpdate: (event) {
        final p = event.localPosition;
        if (p.dx < -18 || p.dx > 44 || p.dy < -18 || p.dy > 58) _stop();
      },
      child: SizedBox(
        width: 26,
        height: 40,
        child: Icon(
          widget.icon,
          size: 18,
          color: widget.onStep == null ? Colors.white24 : Colors.white60,
        ),
      ),
    ),
  );
}
