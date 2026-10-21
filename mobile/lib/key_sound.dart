import 'package:audioplayers/audioplayers.dart';

import 'settings.dart';

enum KeyKind { key, space, enter }

/// Round-robin pool of low-latency players so rapid typing never cuts a click short.
class KeySound {
  KeySound._();
  static final KeySound instance = KeySound._();

  static const _poolSize = 6;
  final Map<KeyKind, List<AudioPlayer>> _pools = {};
  final Map<KeyKind, int> _next = {};
  String? _loadedPack;

  Future<void> _load(String pack) async {
    for (final kind in KeyKind.values) {
      for (final p in _pools[kind] ?? const <AudioPlayer>[]) {
        await p.dispose();
      }
      final players = <AudioPlayer>[];
      for (var i = 0; i < _poolSize; i++) {
        final p = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setSource(AssetSource('sounds/${pack}_${kind.name}.wav'));
        players.add(p);
      }
      _pools[kind] = players;
      _next[kind] = 0;
    }
    _loadedPack = pack;
  }

  Future<void> init() => _load(Settings.instance.pack);

  Future<void> reloadIfNeeded() async {
    if (_loadedPack != Settings.instance.pack)
      await _load(Settings.instance.pack);
  }

  void play(KeyKind kind) {
    final s = Settings.instance;
    if (!s.sound) return;
    final pool = _pools[kind];
    if (pool == null) return;
    final i = _next[kind]!;
    _next[kind] = (i + 1) % pool.length;
    final p = pool[i];
    p.setVolume(s.volume);
    p.stop().then((_) => p.resume());
  }
}
