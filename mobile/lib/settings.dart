import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'modes.dart';

/// One computer the phone can control (each runs its own desktop agent).
class Device {
  Device({
    required this.id,
    this.name = '',
    this.host = '',
    this.port = 8765,
    this.token = '',
    this.useWifi = true,
    this.useBt = false,
    this.useUsb = false,
    this.btAddress = '',
    this.btName = '',
    this.transport = 'wifi',
    this.computerId = '',
  });

  final String id;
  String name;
  String host;
  int port;
  String token;

  // Transports. Both can be on at once so switching needs no reconnect.
  bool useWifi;
  bool useBt;

  /// The USB cable (adb reverse to the agent). Set up automatically when the agent finds
  /// the phone plugged in.
  bool useUsb;
  String btAddress;
  String btName;

  /// Which computer this is, the same after the agent restarts (the token is not). Used to
  /// recognise a computer that is already in the list instead of adding it a second time.
  String computerId;
  String transport; // the one input is sent on: 'wifi' | 'bluetooth' (USB is used automatically while plugged in)

  String get title => name.isNotEmpty
      ? name
      : (host.isNotEmpty
            ? host
            : (btName.isNotEmpty ? btName : 'USB computer'));

  Device copy() => Device.fromJson(toJson());

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'token': token,
    'useWifi': useWifi,
    'useBt': useBt,
    'useUsb': useUsb,
    'btAddress': btAddress,
    'btName': btName,
    'transport': transport,
    'computerId': computerId,
  };

  factory Device.fromJson(Map<String, dynamic> j) => Device(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    host: j['host'] as String? ?? '',
    port: j['port'] as int? ?? 8765,
    token: j['token'] as String? ?? '',
    useWifi: j['useWifi'] as bool? ?? true,
    useBt: j['useBt'] as bool? ?? false,
    useUsb: j['useUsb'] as bool? ?? false,
    btAddress: j['btAddress'] as String? ?? '',
    btName: j['btName'] as String? ?? '',
    transport: j['transport'] as String? ?? 'wifi',
    computerId: j['computerId'] as String? ?? '',
  );

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();
}

class Settings extends ChangeNotifier {
  Settings._();
  static final Settings instance = Settings._();

  late SharedPreferences _p;

  final List<Device> devices = [];

  bool sound = true;
  bool haptic = true;
  double volume = 0.8;
  String pack = 'mechanical';
  double pointerSpeed = 1.5;
  double gyroSpeed = 900;
  bool naturalScroll = true;

  /// Two fingers swiped sideways on the touchpad: right to left = Back, left to right = Forward
  /// (Alt+Left / Alt+Right: browser, file manager). Sideways two-finger scrolling is off then.
  bool padSwipeNav = true;
  bool invertGyro = false;
  bool tapToClick = true;

  /// Use the notch area and turn the top bar into a bar of icons around the notch.
  String notchBar = 'auto';

  /// The bar as icons around the camera notch (always).
  bool get sideBar => notchBar == 'on';
  set sideBar(bool v) => notchBar = v ? 'on' : 'off';

  /// Whether the screen is laid out around the camera notch: always ('on'), never ('off'), or
  /// whenever the phone has a notch ('auto', the default).
  bool useNotchBar({required bool hasNotch}) =>
      notchBar == 'on' || (notchBar == 'auto' && hasNotch);

  /// Order of the modes: where the app starts, what a tap on the mode button
  /// cycles through, and the order of the long-press menu.
  List<String> modeOrder = [for (final m in defaultModeOrder) m.name];

  List<Mode> get modeOrderList => completeOrder(parseModeOrder(modeOrder));

  /// Edge controls on the touchpad: left edge = volume, right edge = brightness, top edge = next / previous track.
  bool padZones = true;

  /// The touchpad reacts to touches. Off: the pad is blank and ignores them.
  bool padEnabled = true;
  bool padPhoneMediaButton = true;

  /// The bottom strip of the pad switches windows (Alt+Tab).
  bool padWindows = true;

  /// Move the cursor with the phone's motion while a finger rests on the touchpad, like an air
  /// mouse (see motion_cursor.dart).
  bool padMotion = false;
  double padMotionSpeed = 900;

  /// Motion moves the cursor without a finger on the pad, and a finger can move it at the same
  /// time. Off: motion only counts while one finger rests on the pad (the finger is a clutch).
  bool padMotionAlways = false;
  bool padMotionInvert = false;

  /// The bottom strip can switch browser tabs too (tap its centre icon to flip between
  /// windows and tabs). [switchTabs] is the mode it is in now.
  bool padTabSwitch = true;
  bool switchTabs = false;

  /// What the bottom strip switches right now.
  bool get tabsMode => padTabSwitch && switchTabs;

  /// What sliding along the top edge does: 'seek' (forward / backward) or 'track' (next / previous).
  String padTopMode = 'seek';

  /// How fast forward / backward goes when holding or sliding on the top edge (1 slow ... 5 fast).
  int seekSpeed = 3;

  /// Go to the keyboard screen by itself when a text field gets focus on the computer.
  bool autoKeyboard = true;

  /// When connected by USB, set up Wi-Fi and Bluetooth for that computer too (the agent tells
  /// the phone how to reach it), so they take over when the cable is unplugged.
  bool usbSync = true;

  /// The corner button that fans out Copy, Cut, Paste, Undo, Select all.
  bool editMenu = true;

  /// A menu opened by a tap stays open after an option is chosen, so Backspace, Enter and the
  /// like can be tapped again and again (it still closes by itself after a few idle seconds).
  bool editMenuStayOpen = true;

  /// Selecting text with the pointer (drag, double or triple click) copies it, like Claude Code.
  bool copyOnSelect = true;

  /// What the edit menu holds: rows split by ';', option ids by ',' (see edit_menu.dart).
  /// Empty: the standard rows.
  String editLayout = '';

  /// Holding Backspace, Delete, Enter ... in the menu repeats it.
  bool editMenuHoldRepeat = true;

  /// The user's own keys for the edit menu (see custom_key.dart), as JSON.
  String editCustom = '';

  /// An open menu folds away after this many idle seconds.
  int editMenuIdleSeconds = 6;

  /// ... but only right after you click with the touchpad pointer, not when the focus moves
  /// by itself (a window opens, a tab changes).
  bool autoKeyboardOnClick = false;

  /// `soft`, `amoled` or `tinted` (see AppTheme) and the accent colour (ARGB).
  String theme = 'soft';
  int accent = 0xFF4F8CFF;

  /// Phone screen brightness while each screen is showing: 0 = leave it to the system,
  /// otherwise 0.1 ... 1.0.
  double brightKeyboard = 0, brightPad = 0, brightMouse = 0;

  double brightnessFor(String mode) => switch (mode) {
    'keyboard' => brightKeyboard,
    'pad' => brightPad,
    'mouse' => brightMouse,
    'mobile' => brightPad,
    _ => 0,
  };

  /// A 3-finger swipe down on the touchpad takes a screenshot on the computer (Print Screen).
  bool screenshotSwipe = true;

  /// Show the Left / Right buttons under the touchpad. Off: the pad fills the whole area.
  bool padButtons = true;

  /// Show the Mouse (tilt) and Mousepad (touchpad) tabs.
  bool mouseTab = true;
  bool padTab = true;

  /// The Voice screen (microphone: dictate text, speak commands).
  bool voiceTab = true;
  bool mobileTab = true;

  /// Hold the button while talking (off: tap once to start, once to stop).
  bool voiceHold = true;

  /// A command the phrase list does not know is guessed by the small model on the computer, and
  /// offered with a "Run it?" question. Off until switched on: the model once froze the
  /// developer's computer (cause not found), so it is opt-in.
  bool voiceAi = false;

  /// Press Enter after dictated text.
  bool voiceEnter = false;

  /// A space after dictated text, so the next dictation does not stick to it.
  bool voiceSpace = true;

  /// Ask before closing a window by voice.
  bool voiceConfirmRisky = true;

  /// One key for Backspace and Del: swipe it sideways to switch between them.
  bool joinDelete = false;

  /// Show the F1-F12 row. Off: the row is hidden and the keyboard gets taller keys.
  bool fnRow = true;

  /// Show the Fn key (F1-F12 become brightness, volume and media keys).
  bool fnKey = true;

  /// Reconnect on app start to the computers that were connected last time.
  bool autoReconnect = true;

  /// Stream the active computer's playback to this phone or another connected agent.
  bool remoteAudioEnabled = true;
  bool remoteAudioAutoReconnect = false;
  bool remoteAudioPlaySource = false;
  bool remoteAudioPlayPhone = false;
  String remoteAudioSource = 'computer';
  String remoteAudioLatency = 'balanced';
  String remoteAudioLastDestination = 'phone';

  /// Ids of the computers that were connected when the app was last used,
  /// and the one that was receiving input.
  List<String> lastConnected = [];
  String lastActiveId = '';

  static const packs = ['mechanical', 'soft', 'typewriter'];

  /// A saved computer that is the same as [d] (other than [d] itself): the same computer id, the
  /// same pairing token, the same Wi-Fi address and port, or the same Bluetooth device.
  Device? findSame(Device d) {
    for (final o in devices) {
      if (o.id == d.id) continue;
      if (d.computerId.isNotEmpty && o.computerId == d.computerId) return o;
      if (d.token.isNotEmpty && o.token == d.token) return o;
      if (d.host.isNotEmpty && o.host == d.host && o.port == d.port) return o;
      if (d.btAddress.isNotEmpty &&
          o.btAddress.toUpperCase() == d.btAddress.toUpperCase()) {
        return o;
      }
    }
    return null;
  }

  Device? deviceById(String id) {
    for (final d in devices) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    sound = _p.getBool('sound') ?? true;
    haptic = _p.getBool('haptic') ?? true;
    volume = _p.getDouble('volume') ?? 0.8;
    pack = _p.getString('pack') ?? 'mechanical';
    pointerSpeed = _p.getDouble('pointerSpeed') ?? 1.5;
    gyroSpeed = _p.getDouble('gyroSpeed') ?? 900;
    naturalScroll = _p.getBool('naturalScroll') ?? true;
    padSwipeNav = _p.getBool('padSwipeNav') ?? true;
    invertGyro = _p.getBool('invertGyro') ?? false;
    tapToClick = _p.getBool('tapToClick') ?? true;
    autoReconnect = _p.getBool('autoReconnect') ?? true;
    remoteAudioEnabled = _p.getBool('remoteAudioEnabled') ?? true;
    remoteAudioAutoReconnect = _p.getBool('remoteAudioAutoReconnect') ?? false;
    remoteAudioPlaySource = _p.getBool('remoteAudioPlaySource') ?? false;
    remoteAudioPlayPhone = _p.getBool('remoteAudioPlayPhone') ?? false;
    remoteAudioSource = _p.getString('remoteAudioSource') == 'phone'
        ? 'phone'
        : 'computer';
    remoteAudioLatency = _p.getString('remoteAudioLatency') ?? 'balanced';
    if (!const ['low', 'balanced'].contains(remoteAudioLatency)) {
      remoteAudioLatency = 'balanced';
    }
    remoteAudioLastDestination =
        _p.getString('remoteAudioLastDestination') ?? 'phone';
    final bar = _p.getString('notchBar');
    notchBar = const {'auto', 'on', 'off'}.contains(bar)
        ? bar!
        : (_p.getBool('sideBar') == true ? 'on' : 'auto');
    fnKey = _p.getBool('fnKey') ?? true;
    fnRow = _p.getBool('fnRow') ?? true;
    joinDelete = _p.getBool('joinDelete') ?? false;
    mouseTab = _p.getBool('mouseTab') ?? true;
    padButtons = _p.getBool('padButtons') ?? true;
    screenshotSwipe = _p.getBool('screenshotSwipe') ?? true;
    padZones = _p.getBool('padZones') ?? true;
    padEnabled = _p.getBool('padEnabled') ?? true;
    padPhoneMediaButton = _p.getBool('padPhoneMediaButton') ?? true;
    padWindows = _p.getBool('padWindows') ?? true;
    padMotion = _p.getBool('padMotion') ?? false;
    padMotionSpeed = (_p.getDouble('padMotionSpeed') ?? 900).clamp(200, 2500);
    padMotionAlways = _p.getBool('padMotionAlways') ?? false;
    padMotionInvert = _p.getBool('padMotionInvert') ?? false;
    padTabSwitch = _p.getBool('padTabSwitch') ?? true;
    switchTabs = _p.getBool('switchTabs') ?? false;
    padTopMode = _p.getString('padTopMode') ?? 'seek';
    seekSpeed = (_p.getInt('seekSpeed') ?? 3).clamp(1, 5);
    autoKeyboard = _p.getBool('autoKeyboard') ?? true;
    usbSync = _p.getBool('usbSync') ?? true;
    editMenu = _p.getBool('editMenu') ?? true;
    editMenuStayOpen = _p.getBool('editMenuStayOpen') ?? true;
    copyOnSelect = _p.getBool('copyOnSelect') ?? true;
    editLayout = _p.getString('editLayout') ?? '';
    editMenuHoldRepeat = _p.getBool('editMenuHoldRepeat') ?? true;
    editCustom = _p.getString('editCustom') ?? '';
    editMenuIdleSeconds = (_p.getInt('editMenuIdleSeconds') ?? 6).clamp(2, 30);
    autoKeyboardOnClick = _p.getBool('autoKeyboardOnClick') ?? false;
    theme = _p.getString('theme') ?? 'soft';
    if (!const ['soft', 'amoled', 'tinted'].contains(theme)) theme = 'soft';
    accent = _p.getInt('accent') ?? 0xFF4F8CFF;
    brightKeyboard = (_p.getDouble('brightKeyboard') ?? 0).clamp(0, 1);
    brightPad = (_p.getDouble('brightPad') ?? 0).clamp(0, 1);
    brightMouse = (_p.getDouble('brightMouse') ?? 0).clamp(0, 1);
    modeOrder =
        _p.getStringList('modeOrder') ??
        [for (final m in defaultModeOrder) m.name];
    padTab = _p.getBool('padTab') ?? true;
    voiceTab = _p.getBool('voiceTab') ?? true;
    mobileTab = _p.getBool('mobileTab') ?? true;
    voiceHold = _p.getBool('voiceHold') ?? true;
    voiceAi = _p.getBool('voiceAi') ?? false;
    voiceEnter = _p.getBool('voiceEnter') ?? false;
    voiceSpace = _p.getBool('voiceSpace') ?? true;
    voiceConfirmRisky = _p.getBool('voiceConfirmRisky') ?? true;
    lastConnected = _p.getStringList('lastConnected') ?? [];
    lastActiveId = _p.getString('lastActiveId') ?? '';

    devices.clear();
    final raw = _p.getString('devices');
    if (raw != null) {
      for (final j in jsonDecode(raw) as List<dynamic>) {
        devices.add(Device.fromJson(j as Map<String, dynamic>));
      }
    } else {
      // Older versions kept a single computer in flat keys; carry it over.
      final host = _p.getString('host') ?? '';
      final bt = _p.getString('btAddress') ?? '';
      if (host.isNotEmpty || bt.isNotEmpty) {
        devices.add(
          Device(
            id: Device.newId(),
            name: 'My PC',
            host: host,
            port: _p.getInt('port') ?? 8765,
            token: _p.getString('token') ?? '',
            useWifi: _p.getBool('useWifi') ?? true,
            useBt: _p.getBool('useBt') ?? false,
            btAddress: bt,
            btName: _p.getString('btName') ?? '',
            transport: _p.getString('transport') ?? 'wifi',
          ),
        );
      }
    }
  }

  void update(void Function() change) {
    change();
    _p.setBool('sound', sound);
    _p.setBool('haptic', haptic);
    _p.setDouble('volume', volume);
    _p.setString('pack', pack);
    _p.setDouble('pointerSpeed', pointerSpeed);
    _p.setDouble('gyroSpeed', gyroSpeed);
    _p.setBool('naturalScroll', naturalScroll);
    _p.setBool('padSwipeNav', padSwipeNav);
    _p.setBool('invertGyro', invertGyro);
    _p.setBool('tapToClick', tapToClick);
    _p.setBool('autoReconnect', autoReconnect);
    _p.setBool('remoteAudioEnabled', remoteAudioEnabled);
    _p.setBool('remoteAudioAutoReconnect', remoteAudioAutoReconnect);
    _p.setBool('remoteAudioPlaySource', remoteAudioPlaySource);
    _p.setBool('remoteAudioPlayPhone', remoteAudioPlayPhone);
    _p.setString('remoteAudioSource', remoteAudioSource);
    _p.setString('remoteAudioLatency', remoteAudioLatency);
    _p.setString('remoteAudioLastDestination', remoteAudioLastDestination);
    _p.setString('notchBar', notchBar);
    _p.setBool('fnKey', fnKey);
    _p.setBool('fnRow', fnRow);
    _p.setBool('joinDelete', joinDelete);
    _p.setBool('mouseTab', mouseTab);
    _p.setBool('padButtons', padButtons);
    _p.setBool('screenshotSwipe', screenshotSwipe);
    _p.setBool('padZones', padZones);
    _p.setBool('padEnabled', padEnabled);
    _p.setBool('padPhoneMediaButton', padPhoneMediaButton);
    _p.setBool('padWindows', padWindows);
    _p.setBool('padMotion', padMotion);
    _p.setDouble('padMotionSpeed', padMotionSpeed);
    _p.setBool('padMotionAlways', padMotionAlways);
    _p.setBool('padMotionInvert', padMotionInvert);
    _p.setBool('padTabSwitch', padTabSwitch);
    _p.setBool('switchTabs', switchTabs);
    _p.setString('padTopMode', padTopMode);
    _p.setInt('seekSpeed', seekSpeed);
    _p.setBool('autoKeyboard', autoKeyboard);
    _p.setBool('usbSync', usbSync);
    _p.setBool('editMenu', editMenu);
    _p.setBool('editMenuStayOpen', editMenuStayOpen);
    _p.setBool('copyOnSelect', copyOnSelect);
    _p.setString('editLayout', editLayout);
    _p.setBool('editMenuHoldRepeat', editMenuHoldRepeat);
    _p.setString('editCustom', editCustom);
    _p.setInt('editMenuIdleSeconds', editMenuIdleSeconds);
    _p.setBool('autoKeyboardOnClick', autoKeyboardOnClick);
    _p.setString('theme', theme);
    _p.setInt('accent', accent);
    _p.setDouble('brightKeyboard', brightKeyboard);
    _p.setDouble('brightPad', brightPad);
    _p.setDouble('brightMouse', brightMouse);
    _p.setStringList('modeOrder', modeOrder);
    _p.setBool('padTab', padTab);
    _p.setBool('voiceTab', voiceTab);
    _p.setBool('mobileTab', mobileTab);
    _p.setBool('voiceHold', voiceHold);
    _p.setBool('voiceAi', voiceAi);
    _p.setBool('voiceEnter', voiceEnter);
    _p.setBool('voiceSpace', voiceSpace);
    _p.setBool('voiceConfirmRisky', voiceConfirmRisky);
    _p.setStringList('lastConnected', lastConnected);
    _p.setString('lastActiveId', lastActiveId);
    _p.setString('devices', jsonEncode([for (final d in devices) d.toJson()]));
    notifyListeners();
  }

  /// Add a new device or replace the one with the same id.
  void saveDevice(Device d) => update(() {
    final i = devices.indexWhere((x) => x.id == d.id);
    if (i >= 0) {
      devices[i] = d;
    } else {
      devices.add(d);
    }
  });

  void removeDevice(String id) => update(() {
    devices.removeWhere((d) => d.id == id);
    lastConnected.remove(id);
    if (lastActiveId == id) lastActiveId = '';
  });
}
