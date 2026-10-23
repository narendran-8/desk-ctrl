import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'links.dart';
import 'scan_screen.dart' show PairInfo;
import 'settings.dart';

export 'links.dart' show Transport, LinkState, TransportInfo;

enum Phase {
  /// Not connected.
  idle,

  /// First attempt in progress; nothing has come up yet.
  connecting,

  /// At least one link has been up. Links that drop are retried in the background.
  active,
}

/// The connection to ONE computer: its Wi-Fi and Bluetooth links. Both can be
/// up at once, so switching transport only changes which one traffic goes out
/// on. If the chosen link drops, traffic moves to the other by itself and
/// returns when the chosen one is back.
class Session extends ChangeNotifier {
  /// Whether the focus on this computer was last reported to be on something you can type into.
  bool? focusTypeable;

  /// A text field got focus on this computer.
  void Function(bool typeable)? onTextFocus;

  /// A piece of the computer's answer to the voice screen.
  void Function(Uint8List frame)? onVoice;

  Session(this.device) {
    for (final l in [wifi, bt, usb]) {
      l.addListener(_linksChanged);
      l.onLost = () => _lost(l.transport);
      l.onLeds = _setLeds;
      l.onVoice = (f) => onVoice?.call(f);
      l.onLevels = _setLevels;
      l.onTextFocus = (t) {
        focusTypeable = t;
        onTextFocus?.call(t);
      };
    }
    usb.onInfo = _usbInfo;
  }

  Device device;

  /// What could not be set up from the information the computer sent over the cable (for
  /// example: its Bluetooth is not paired with this phone). Shown with the links.
  String? syncNote;

  /// The computer, over the USB cable, says how to reach it by Wi-Fi and Bluetooth. Always
  /// remembered as this computer's id (so it is not added twice); the Wi-Fi address and the
  /// Bluetooth device are set up too when "set up Wi-Fi and Bluetooth over USB" is on. The
  /// links are then brought up, so they are ready when the cable is pulled out.
  Future<void> _usbInfo(String text) async {
    final Map<String, String> q;
    try {
      q = Uri.splitQueryString(text);
    } catch (_) {
      return;
    }
    final st = Settings.instance;
    final d = device;
    var changed = false;
    final id = q['id'] ?? '';
    if (id.isNotEmpty && d.computerId != id) {
      d.computerId = id;
      changed = true;
    }
    if (d.name.isEmpty && (q['name'] ?? '').isNotEmpty) {
      d.name = q['name']!;
      changed = true;
    }
    if (st.usbSync) {
      final ip = q['ip'] ?? '';
      final port = int.tryParse(q['port'] ?? '') ?? d.port;
      if (ip.isNotEmpty && (d.host != ip || d.port != port || !d.useWifi)) {
        d.host = ip;
        d.port = port;
        d.useWifi = true;
        changed = true;
      }
      final bt = (q['bt'] ?? '').toUpperCase();
      if (bt.isNotEmpty && !(d.useBt && d.btAddress.toUpperCase() == bt)) {
        try {
          if (await BtLink.ensurePermission()) {
            final match = (await BtLink.bondedDevices())
                .where((x) => x.address.toUpperCase() == bt)
                .firstOrNull;
            if (match != null) {
              d.btAddress = match.address;
              d.btName = match.name;
              d.useBt = true;
              changed = true;
              syncNote = null;
            } else {
              syncNote =
                  'Bluetooth not set up: pair this phone with the computer ($bt) in '
                  'Android Bluetooth settings, then plug in again.';
            }
          } else {
            syncNote = 'Bluetooth not set up: permission denied.';
          }
        } catch (e) {
          syncNote = 'Bluetooth not set up: ${Link.describe(e)}';
        }
        notifyListeners();
      }
    }
    // The same computer may already be in the list under another entry (added by Wi-Fi or
    // Bluetooth before it had an id, or the agent restarted with a new token): join them.
    final other = st.findSame(d);
    if (other != null) {
      await Connection.instance.mergeInto(other, d);
      await Connection.instance
          .dedupeAll(); // and any others that are the same computer
      return;
    }
    if (changed) st.saveDevice(d);
    if (!st.usbSync) return;
    if (d.useWifi && d.host.isNotEmpty) startLink(Transport.wifi);
    if (d.useBt && d.btAddress.isNotEmpty) startLink(Transport.bluetooth);
  }

  /// Called when traffic moves to the other link: one went down, or the preferred one is back.
  void Function(Transport to)? onSwitched;
  Transport? _lastEffective;

  void _linksChanged() {
    final now = effective?.transport;
    if (now != _lastEffective) {
      final was = _lastEffective;
      _lastEffective = now;
      if (was != null && now != null) onSwitched?.call(now);
    }
    notifyListeners();
  }

  /// Lock-key lights of this computer (bit0 Caps, bit1 Num, bit2 Scroll); null until it reports.
  int? leds;

  /// Volume and brightness (percent) of this computer; null until it reports them or
  /// when it cannot.
  int? volume, brightness;
  bool muted = false;

  /// The computer has sent a report at least once (older agents never do).
  bool levelsKnown = false;

  void _setLevels(int vol, int bright, bool mute) {
    final v = vol == 0xFF ? null : vol, b = bright == 0xFF ? null : bright;
    final first = !levelsKnown;
    levelsKnown = true;
    if (!first && v == volume && b == brightness && mute == muted) return;
    volume = v;
    brightness = b;
    muted = mute;
    notifyListeners();
  }

  void _setLeds(int flags) {
    if (leds == flags) return;
    leds = flags;
    notifyListeners();
  }

  final WifiLink wifi = WifiLink();
  final BtLink bt = BtLink();
  final UsbLink usb = UsbLink();

  Phase phase = Phase.idle;
  String? error;

  /// The transport picked for sending.
  Transport preferred = Transport.wifi;

  Set<Transport> _wanted = {};
  int _session = 0;
  final Map<Transport, Timer> _retry = {};
  final Map<Transport, int> _attempts = {};

  Link link(Transport t) => switch (t) {
    Transport.wifi => wifi,
    Transport.bluetooth => bt,
    Transport.usb => usb,
  };

  bool wants(Transport t) => _wanted.contains(t);

  @visibleForTesting
  void debugWant(Transport t) => _wanted.add(t);

  /// The link traffic goes out on right now, or null if both are down.
  ///
  /// The cable comes first while it is plugged in (the fastest and steadiest link); after
  /// that the transport picked by the user, then the others.
  Link? get effective {
    if (usb.connected) return usb;
    final p = link(preferred);
    if (p.connected) return p;
    for (final t in [Transport.wifi, Transport.bluetooth]) {
      if (t != preferred && link(t).connected) return link(t);
    }
    return null;
  }

  /// Traffic goes out on another link than the one picked, because that one is down. The
  /// cable being used on purpose does not count.
  bool get usingFallback =>
      effective != null &&
      effective!.transport != preferred &&
      effective!.transport != Transport.usb;

  void send(Uint8List payload) => effective?.send(payload);

  // ---- lifecycle -----------------------------------------------------------

  /// Brings up every transport enabled for this device. Completes after the
  /// first round of attempts; [phase] says whether anything came up.
  ///
  /// With [keepTrying] (the computer was connected last time) a first round that finds nothing
  /// is not the end: the phone keeps looking every few seconds, so starting the desktop agent
  /// after the app connects it with no scan or cable.
  Future<void> connect({bool keepTrying = false}) async {
    final d = device;
    final wanted = <Transport>{
      if (d.useWifi) Transport.wifi,
      if (d.useBt) Transport.bluetooth,
      if (d.useUsb) Transport.usb,
    };
    final String? problem = wanted.isEmpty
        ? 'Turn on Wi-Fi, Bluetooth or both.'
        : d.useWifi && d.host.isEmpty
        ? 'Enter the desktop IP address.'
        : d.useBt && d.btAddress.isEmpty
        ? 'Choose a paired Bluetooth device.'
        : null;
    if (problem != null) {
      error = problem;
      notifyListeners();
      return;
    }

    await disconnect();
    final session = ++_session;
    _wanted = wanted;
    final pref = d.transport == Transport.bluetooth.name
        ? Transport.bluetooth
        : Transport.wifi;
    final others = wanted.where((t) => t != Transport.usb);
    preferred = wanted.contains(pref)
        ? pref
        : others.isNotEmpty
        ? others.first
        : Transport.usb;
    for (final t in wanted) {
      _configure(t);
    }
    phase = Phase.connecting;
    error = null;
    notifyListeners();

    await Future.wait([for (final t in wanted) _openFirst(t, session)]);
    if (session != _session) return;

    if (phase == Phase.connecting) {
      // Nothing came up.
      phase = Phase.idle;
      error = [
        for (final t in wanted) '${t.label}: ${link(t).error ?? 'failed'}',
      ].join('\n');
      notifyListeners();
      if (keepTrying) _waitForComputer(session);
    } else {
      // Something is up; keep trying the others in the background.
      for (final t in wanted) {
        _scheduleRetry(t);
      }
    }
  }

  Timer? _waiter;

  /// Still looking for this computer after the app started (see `connect(keepTrying)`).
  bool get waiting => _waiter?.isActive ?? false;

  /// The agent answered but did not accept the saved token: it was started with a new one
  /// (older agents did that on every start), so this phone has to pair again.
  bool get tokenRejected => [
    wifi,
    bt,
    usb,
  ].any((l) => (l.error ?? '').toLowerCase().contains('wrong token'));
  bool _looking = false;

  /// Nothing answered: try again every few seconds until a link comes up (or [disconnect]).
  void _waitForComputer(int session) {
    _waiter?.cancel();
    _waiter = Timer.periodic(waitInterval, (t) async {
      if (session != _session || phase == Phase.active) {
        t.cancel();
        return;
      }
      if (_looking) return;
      _looking = true;
      try {
        for (final w in _wanted) {
          if (link(w).state != LinkState.disconnected) continue;
          _configure(w);
          final ok = await link(w).open();
          if (session != _session) return;
          if (!ok) continue;
          t.cancel();
          _attempts[w] = 0;
          phase = Phase.active;
          error = null;
          notifyListeners();
          for (final other in _wanted) {
            _scheduleRetry(other);
          }
          return;
        }
      } finally {
        _looking = false;
      }
    });
  }

  /// Time between looks for a computer that did not answer at start.
  static Duration waitInterval = const Duration(seconds: 4);

  Future<void> disconnect() async {
    _session++;
    _waiter?.cancel();
    for (final t in _retry.values) {
      t.cancel();
    }
    _retry.clear();
    phase = Phase.idle;
    leds = null;
    levelsKnown = false;
    await Future.wait([wifi.close(), bt.close(), usb.close()]);
    notifyListeners();
  }

  void _configure(Transport t) {
    final d = device;
    switch (t) {
      case Transport.wifi:
        wifi
          ..host = d.host
          ..port = d.port
          ..token = d.token;
      case Transport.bluetooth:
        bt
          ..address = d.btAddress
          ..token = d.token;
      case Transport.usb:
        usb
          ..host = '127.0.0.1'
          ..port = d.port
          ..token = d.token;
    }
  }

  Future<void> _openFirst(Transport t, int session) async {
    final ok = await link(t).open();
    if (session != _session || !ok) return;
    _attempts[t] = 0;
    if (phase == Phase.connecting) {
      phase = Phase.active;
      notifyListeners();
    }
  }

  // ---- switching and recovery ---------------------------------------------

  /// Choose which transport to send on. Instant when that link is already up.
  void setPreferred(Transport t) {
    preferred = t;
    Settings.instance.update(() => device.transport = t.name);
    if (phase == Phase.active && link(t).state == LinkState.disconnected) {
      startLink(t);
    }
    notifyListeners();
  }

  /// Bring a link up now (or retry it), also if it was not chosen at connect time.
  void startLink(Transport t) {
    if (phase != Phase.active) return;
    final l = link(t);
    if (l.state != LinkState.disconnected) return;
    _configure(t);
    final missing = switch (t) {
      Transport.wifi => wifi.host.isEmpty,
      Transport.bluetooth => bt.address.isEmpty,
      Transport.usb => false,
    };
    if (missing) {
      l.setState(
        LinkState.disconnected,
        t == Transport.wifi
            ? 'No address set'
            : 'No Bluetooth device set for this computer',
      );
      return;
    }
    _wanted.add(t);
    _retry.remove(t)?.cancel();
    _attempts[t] = 0;
    _tryOpen(t, _session);
  }

  void _tryOpen(Transport t, int session) {
    link(t).open().then((ok) {
      if (session != _session) return;
      if (ok) {
        _attempts[t] = 0;
      } else {
        _scheduleRetry(t);
      }
    });
  }

  void _lost(Transport t) {
    if (phase != Phase.active) return;
    _attempts[t] = 0;
    _scheduleRetry(t);
  }

  void _scheduleRetry(Transport t) {
    if (phase != Phase.active || !_wanted.contains(t)) return;
    // Connected, or another open() is already running for this link.
    if (link(t).state != LinkState.disconnected) return;
    _retry.remove(t)?.cancel();
    final n = _attempts[t] = (_attempts[t] ?? 0) + 1;
    final session = _session;
    _retry[t] = Timer(Duration(seconds: math.min(2 * n, 15)), () {
      _retry.remove(t);
      if (session != _session || link(t).state != LinkState.disconnected) {
        return;
      }
      _configure(t);
      _tryOpen(t, session);
    });
  }
}

/// All computers the phone is connected to. Several sessions can be up at the
/// same time; input goes to the active one, and switching is instant because
/// the others stay connected.
///
/// Binary protocol shared with the desktop agent (see agent/src/hid.rs).
class Connection extends ChangeNotifier {
  Connection._();
  static final Connection instance = Connection._();

  final Map<String, Session> _sessions = {};
  String? activeId;
  String? _previousActiveId;

  // Mouse deltas are coalesced and flushed at ~120 Hz.
  int _pdx = 0, _pdy = 0;
  Timer? _flush;

  // Keys and buttons currently held, so they can be released on the old computer when switching.
  final Set<int> _heldKeys = {};
  final Set<int> _heldButtons = {};

  Session session(Device d) {
    final s = _sessions.putIfAbsent(d.id, () {
      final created = Session(d)..addListener(_changed);
      created.onVoice = (f) {
        if (identical(created, active)) onVoice?.call(f);
      };
      created.onTextFocus = (t) {
        if (identical(created, active)) onTextFocus?.call(t);
      };
      // Keys held on the link that went down would stay pressed on the computer;
      // release them on the link that took over.
      created.onSwitched = (_) {
        if (identical(created, active)) _releaseHeld();
      };
      return created;
    });
    s.device = d;
    return s;
  }

  /// The active computer reports that a text field has the focus.
  void Function(bool typeable)? onTextFocus;

  Session? get active => activeId == null ? null : _sessions[activeId];

  bool _localCaps = false;

  /// Volume / brightness of the active computer, in percent (null when unknown).
  int? get volumePct => active?.volume;
  int? get brightnessPct => active?.brightness;
  bool get muted => active?.muted ?? false;
  bool get levelsKnown => active?.levelsKnown ?? false;

  /// The computer reports its levels but has no brightness it can change (a desktop PC
  /// with an external monitor, for example).
  bool get brightnessUnsupported =>
      (active?.levelsKnown ?? false) && active?.brightness == null;

  /// Caps Lock light. Taken from the computer's real light when it reports one,
  /// otherwise guessed by counting Caps presses.
  bool get capsOn {
    final l = active?.leds;
    return l != null ? (l & 1) != 0 : _localCaps;
  }

  bool get anyActive => _sessions.values.any((s) => s.phase == Phase.active);

  int get activeCount =>
      _sessions.values.where((s) => s.phase == Phase.active).length;

  /// Connected computers in the same order as the saved computer list.
  List<String> get connectedDeviceIds => [
    for (final d in Settings.instance.devices)
      if (_sessions[d.id]?.phase == Phase.active) d.id,
  ];

  /// A tap goes back to the previous live computer, then alternates between them.
  /// If that computer went offline, use the next live one instead.
  Future<void> switchToPreviousConnected() async {
    final ids = connectedDeviceIds;
    if (ids.length < 2) return;
    final previous = _previousActiveId;
    if (previous != null && previous != activeId && ids.contains(previous)) {
      await switchTo(previous);
    } else {
      await switchToNextConnected();
    }
  }

  /// A double tap cycles through every currently connected computer.
  Future<void> switchToNextConnected() async {
    final ids = connectedDeviceIds;
    if (ids.length < 2) return;
    final index = ids.indexOf(activeId ?? '');
    await switchTo(ids[(index + 1) % ids.length]);
  }

  void _changed() {
    // Remember every computer that is up, for the next start.
    final up = [
      for (final e in _sessions.entries)
        if (e.value.phase == Phase.active) e.key,
    ];
    final st = Settings.instance;
    if (up.any((id) => !st.lastConnected.contains(id))) {
      st.update(() => st.lastConnected = {...st.lastConnected, ...up}.toList());
    }
    // Keep focus on a live computer: if the active one is gone, move to another.
    if (active == null || active!.phase == Phase.idle) {
      final next = _sessions.entries
          .where((e) => e.value.phase == Phase.active)
          .firstOrNull;
      if (next != null) _focus(next.key);
    }
    if (anyActive) {
      _flush ??= Timer.periodic(
        const Duration(milliseconds: 8),
        (_) => _flushMove(),
      );
    } else {
      _flush?.cancel();
      _flush = null;
      _pdx = _pdy = 0;
    }
    notifyListeners();
  }

  // ---- devices ---------------------------------------------------------------

  /// Connect one saved computer. It becomes active if nothing else is.
  Future<void> connectDevice(String id, {bool keepTrying = false}) async {
    final d = Settings.instance.deviceById(id);
    if (d == null) return;
    await session(d).connect(keepTrying: keepTrying);
  }

  /// The USB cable was pulled out (Android reported it): the cable's link is dropped at once, so
  /// traffic and the connection icon move to Wi-Fi or Bluetooth.
  void cableRemoved() {
    for (final s in _sessions.values) {
      s.usb.cableRemoved();
    }
  }

  Future<void> connectAll() => Future.wait([
    for (final d in Settings.instance.devices) connectDevice(d.id),
  ]);

  /// The user disconnected this computer, so it is not reconnected on the next start.
  Future<void> disconnectDevice(String id) async {
    _forgetLast(id);
    await _sessions[id]?.disconnect();
    _changed();
  }

  Future<void> disconnectAll() async {
    for (final id in _sessions.keys) {
      _forgetLast(id);
    }
    await Future.wait([for (final s in _sessions.values) s.disconnect()]);
  }

  void _forgetLast(String id) {
    final st = Settings.instance;
    if (st.lastConnected.contains(id)) {
      st.update(() => st.lastConnected.remove(id));
    }
  }

  /// On app start: reconnect the computers that were connected last time, with
  /// the one that was receiving input back in focus.
  Future<void> restoreLast() async {
    final st = Settings.instance;
    if (!st.autoReconnect) return;
    final ids = st.lastConnected
        .where((id) => st.deviceById(id) != null)
        .toList();
    if (ids.isEmpty) return;
    if (ids.contains(st.lastActiveId)) {
      activeId = st.lastActiveId;
    } else {
      activeId ??= ids.first; // so the screen can say whom it is looking for
    }
    await Future.wait([
      for (final id in ids) connectDevice(id, keepTrying: true),
    ]);
  }

  /// The agent found the phone plugged in and sent its pairing details over the cable.
  /// The computer is added (or, if it is already known, gets its USB link) and connected,
  /// with no QR code. Returns the device id.
  Future<String> pairOverUsb(PairInfo info) async {
    final st = Settings.instance;
    // The same computer is recognised by its id, or by the token: it is not added a second time.
    final probe = Device(
      id: '',
      token: info.token,
      computerId: info.computerId ?? '',
    );
    var d = st.findSame(probe);
    var tokenChanged = false;
    if (d == null) {
      d = Device(
        id: Device.newId(),
        name: (info.name ?? '').isEmpty ? 'Computer' : info.name!,
        port: info.port,
        token: info.token,
        computerId: info.computerId ?? '',
        useWifi: false,
        useUsb: true,
      );
    } else {
      d.useUsb = true;
      d.port = info.port;
      // The agent was restarted: it has a new token. The cable brought the current one.
      tokenChanged = d.token != info.token;
      d.token = info.token;
      if ((info.computerId ?? '').isNotEmpty) d.computerId = info.computerId!;
    }
    st.saveDevice(d);
    final s = session(d);
    if (tokenChanged) {
      await s.connect(); // every link starts again with the new token
    } else if (s.phase == Phase.active) {
      s.startLink(
        Transport.usb,
      ); // already connected over Wi-Fi / Bluetooth: add the cable
    }
    await switchTo(d.id); // connects it first if it is not up
    return d.id;
  }

  /// Fills [keep] with what [from] knows (the same computer, found twice), removes [from] and
  /// connects [keep]. [keep] stays where it is in the list, with its name.
  Future<void> mergeInto(Device keep, Device from, {bool fromNewer = true}) =>
      _exclusive(() async {
        final st = Settings.instance;
        // Another merge may have removed one of them while this one waited.
        if (keep.id == from.id ||
            st.deviceById(keep.id) == null ||
            st.deviceById(from.id) == null) {
          return;
        }
        mergeFields(keep, from, fromNewer: fromNewer);
        final wasActive = activeId == from.id;
        st.saveDevice(keep);
        await forgetDevice(from.id);
        if (wasActive) {
          await switchTo(keep.id);
        } else {
          await connectDevice(keep.id);
        }
      });

  // Merges run one at a time: while one is still taking a computer apart, a link of the
  // computer it is joined to may report in and start a merge of its own, the other way round.
  Future<void> _mergeLock = Future.value();

  Future<void> _exclusive(Future<void> Function() job) async {
    final before = _mergeLock;
    final done = Completer<void>();
    _mergeLock = done.future;
    await before;
    try {
      await job();
    } finally {
      done.complete();
    }
  }

  /// Copies what [from] knows about the computer into [keep] (not its id or its name).
  ///
  /// [fromNewer]: [from] was saved after [keep], so what it knows is more up to date (the
  /// pairing token above all) and wins; otherwise it only fills in what [keep] lacks.
  static void mergeFields(Device keep, Device from, {bool fromNewer = true}) {
    if (from.token.isNotEmpty && (fromNewer || keep.token.isEmpty))
      keep.token = from.token;
    if (from.computerId.isNotEmpty && (fromNewer || keep.computerId.isEmpty)) {
      keep.computerId = from.computerId;
    }
    if (from.useWifi &&
        from.host.isNotEmpty &&
        (fromNewer || keep.host.isEmpty)) {
      keep.host = from.host;
      keep.port = from.port;
      keep.useWifi = true;
    }
    if (from.useBt &&
        from.btAddress.isNotEmpty &&
        (fromNewer || keep.btAddress.isEmpty)) {
      keep.btAddress = from.btAddress;
      keep.btName = from.btName;
      keep.useBt = true;
    }
    if (from.useUsb) keep.useUsb = true;
    if (keep.name.isEmpty) keep.name = from.name;
  }

  /// Joins every pair of saved computers that are provably the same one (same computer id,
  /// token, Wi-Fi address and port, or Bluetooth device), keeping the entry that is first in the
  /// list. Entries added before the app could recognise a computer pile up like that. Returns how
  /// many were joined.
  Future<int> dedupeAll() async {
    final st = Settings.instance;
    var joined = 0;
    for (var guard = 0; guard < 50; guard++) {
      Device? keep, dup;
      for (final d in st.devices) {
        final o = st.findSame(d);
        if (o == null) continue;
        final earlier = st.devices.indexOf(d) < st.devices.indexOf(o);
        keep = earlier ? d : o;
        dup = earlier ? o : d;
        break;
      }
      if (keep == null || dup == null) break;
      // Device ids are the time they were made: the larger one is the newer entry.
      // A computer that is connected right now has the pairing token that works; otherwise the
      // newer entry is the one to believe.
      final keepLive = _sessions[keep.id]?.phase == Phase.active;
      final dupLive = _sessions[dup.id]?.phase == Phase.active;
      final newer = dupLive != keepLive
          ? dupLive
          : (int.tryParse(dup.id) ?? 0) >= (int.tryParse(keep.id) ?? 0);
      await mergeInto(keep, dup, fromNewer: newer);
      joined++;
    }
    return joined;
  }

  Future<void> forgetDevice(String id) async {
    await disconnectDevice(id);
    _sessions.remove(id);
    if (activeId == id) activeId = null;
    Settings.instance.removeDevice(id);
    _changed();
  }

  /// Make [id] the computer that receives input. Instant if it is connected;
  /// otherwise it is connected first and gets input as soon as it is up.
  Future<void> switchTo(String id) async {
    final d = Settings.instance.deviceById(id);
    if (d == null) return;
    _focus(id);
    final s = session(d);
    if (s.phase == Phase.idle) {
      await s.connect();
      _focus(id); // keep focus even if another computer connected meanwhile
    }
  }

  void _focus(String id) {
    if (activeId == id) return;
    _releaseHeld();
    _pdx = _pdy = 0;
    _previousActiveId = activeId;
    activeId = id;
    final st = Settings.instance;
    if (st.lastActiveId != id) st.update(() => st.lastActiveId = id);
    notifyListeners();
  }

  /// Release anything held on the computer we are leaving, so no key sticks there.
  void _releaseHeld() {
    final s = active;
    if (s == null) return;
    for (final k in _heldKeys) {
      s.send(Uint8List.fromList([0x02, (k >> 8) & 0xFF, k & 0xFF]));
    }
    for (final b in _heldButtons) {
      s.send(Uint8List.fromList([0x04, b, 0]));
    }
    _heldKeys.clear();
    _heldButtons.clear();
  }

  // ---- sending (to the active computer) ---------------------------------------

  /// The voice screen listens here (only the active computer's answers arrive).
  void Function(Uint8List frame)? onVoice;

  /// Send a frame the voice screen made (microphone audio and requests, see voice.dart).
  void sendVoice(List<int> payload) => _send(payload);

  void _send(List<int> payload) => active?.send(Uint8List.fromList(payload));

  static List<int> _i16(int v) => [(v >> 8) & 0xFF, v & 0xFF];

  void key(int hid, bool down) {
    if (hid == 0x39 && down && active?.leds == null) {
      _localCaps = !_localCaps;
      notifyListeners();
    }
    down ? _heldKeys.add(hid) : _heldKeys.remove(hid);
    _send([down ? 0x01 : 0x02, (hid >> 8) & 0xFF, hid & 0xFF]);
  }

  void move(int dx, int dy) {
    _pdx += dx;
    _pdy += dy;
    if (_leftHeld) _dragPx += dx.abs() + dy.abs();
  }

  // ---- copy on select -----------------------------------------------------

  /// Called after a selection was copied (the app shows a small message).
  VoidCallback? onCopied;

  bool _leftHeld = false;
  int _dragPx = 0;
  int _clickRun = 0;
  DateTime _lastLeftDown = DateTime.fromMillisecondsSinceEpoch(0);

  /// Movement while the left button is held that counts as selecting by dragging.
  static const selectDragPx = 24;

  /// Two or three presses this close together select a word or a line.
  static const multiClick = Duration(milliseconds: 450);

  void _leftChanged(bool down) {
    final now = DateTime.now();
    if (down) {
      _clickRun = now.difference(_lastLeftDown) < multiClick
          ? _clickRun + 1
          : 1;
      _lastLeftDown = now;
      _dragPx = 0;
      _leftHeld = true;
      return;
    }
    if (!_leftHeld) return;
    _leftHeld = false;
    if (!Settings.instance.copyOnSelect) return;
    if (_dragPx >= selectDragPx || _clickRun >= 2) {
      // A moment for the program to finish selecting, then Ctrl+Insert: "copy" that never
      // interrupts a program in a terminal the way Ctrl+C does.
      Timer(const Duration(milliseconds: 100), () {
        if (!anyActive) return;
        chord([0xE0], 0x49);
        onCopied?.call();
      });
    }
  }

  void _flushMove() {
    if (_pdx == 0 && _pdy == 0) return;
    final dx = _pdx.clamp(-32768, 32767);
    final dy = _pdy.clamp(-32768, 32767);
    _pdx = _pdy = 0;
    _send([0x03, ..._i16(dx), ..._i16(dy)]);
  }

  /// button: 0 left, 1 right, 2 middle
  /// The active computer's focus is on something you can type into (null: not known).
  bool? get focusTypeable => active?.focusTypeable;

  /// Called when the left button goes down (a click with the pointer).
  VoidCallback? onClick;

  /// When the left button last went down (a tap, or the Left button under the pad).
  DateTime lastClickAt = DateTime.fromMillisecondsSinceEpoch(0);

  void button(int button, bool down) {
    if (down && button == 0) {
      lastClickAt = DateTime.now();
      onClick?.call();
    }
    if (button == 0) _leftChanged(down);
    _flushMove();
    down ? _heldButtons.add(button) : _heldButtons.remove(button);
    _send([0x04, button, down ? 1 : 0]);
  }

  void click(int button) {
    this.button(button, true);
    this.button(button, false);
  }

  /// Press modifiers + key together, then release (e.g. Ctrl+Alt+Left).
  void chord(List<int> mods, int hid) {
    for (final m in mods) {
      key(m, true);
    }
    key(hid, true);
    key(hid, false);
    for (final m in mods.reversed) {
      key(m, false);
    }
  }

  void scroll(int dx, int dy) => _send([0x05, ..._i16(dx), ..._i16(dy)]);
}
