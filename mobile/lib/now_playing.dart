import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class NowPlaying {
  const NowPlaying({
    this.title = '',
    this.app = '',
    this.playing = false,
    this.icon,
  });
  final String title, app;
  final bool playing;
  final Uint8List? icon;

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
        width: 40,
        height: 36,
        child: Column(
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
              const Icon(Icons.music_note, size: 16, color: Colors.white54),
            const SizedBox(height: 3),
            SizedBox(
              height: 14,
              child: _TrackTitle(
                key: ValueKey('${media.app}:${media.title}'),
                title: media.title,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackTitle extends StatefulWidget {
  const _TrackTitle({super.key, required this.title});
  final String title;
  @override
  State<_TrackTitle> createState() => _TrackTitleState();
}

class _TrackTitleState extends State<_TrackTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scroll = AnimationController(vsync: this);
  static const style = TextStyle(color: Colors.white60, fontSize: 10);
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
