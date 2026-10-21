import 'package:flutter/material.dart';

import 'connection.dart';
import 'links.dart';
import 'scan_screen.dart';
import 'settings.dart';

/// Add a computer, or edit a saved one. Saving connects it.
class DeviceFormScreen extends StatefulWidget {
  final Device? editing;
  const DeviceFormScreen({super.key, this.editing});

  @override
  State<DeviceFormScreen> createState() => _DeviceFormScreenState();
}

class _DeviceFormScreenState extends State<DeviceFormScreen> {
  final c = Connection.instance;

  late final Device d =
      widget.editing?.copy() ??
      Device(
        id: Device.newId(),
        name: 'Computer ${Settings.instance.devices.length + 1}',
      );
  late final _name = TextEditingController(text: d.name);
  late final _host = TextEditingController(text: d.host);
  late final _port = TextEditingController(text: d.port.toString());
  late final _token = TextEditingController(text: d.token);

  List<BtDevice> _devices = [];
  String? _btNote;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (d.useBt) _loadDevices();
  }

  Future<void> _loadDevices() async {
    String? note;
    try {
      if (!await BtLink.ensurePermission()) {
        note = 'Bluetooth permission denied';
      } else {
        _devices = await BtLink.bondedDevices();
        if (_devices.isEmpty) {
          note = 'No paired devices. Pair this phone with your PC in Android Bluetooth settings first.';
        }
      }
    } catch (e) {
      note = Link.describe(e);
    }
    if (mounted) setState(() => _btNote = note);
  }

  void _apply() {
    d.name = _name.text.trim();
    d.host = _host.text.trim();
    d.port = int.tryParse(_port.text.trim()) ?? 8765;
    d.token = _token.text.trim();
    if (d.name.isEmpty) d.name = d.host.isNotEmpty ? d.host : d.btName;
  }

  Future<void> _connect() async {
    _apply();
    // A computer that is already in the list is updated, not added again.
    var target = d;
    if (widget.editing == null) {
      final dup = Settings.instance.findSame(d);
      if (dup != null) {
        Connection.mergeFields(dup, d);
        target = dup;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              '"${dup.title}" is already in your list - updated it.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    Settings.instance.saveDevice(target);
    setState(() {
      _busy = true;
      _error = null;
    });
    await c.connectDevice(target.id);
    if (!mounted) return;
    final s = c.session(target);
    if (s.phase == Phase.active) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = s.error;
      });
    }
  }

  Future<void> _cancel() async {
    await c.disconnectDevice(d.id);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _scan() async {
    final info = await Navigator.of(context)
        .push<PairInfo>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (info == null) return;

    _token.text = info.token;
    if ((info.computerId ?? '').isNotEmpty) d.computerId = info.computerId!;
    if (info.ip != null) {
      _host.text = info.ip!;
      _port.text = info.port.toString();
    }
    var useBt = false;
    String? note;
    if (info.bt != null) {
      await _loadDevices();
      final match = _devices
          .where((x) => x.address.toUpperCase() == info.bt)
          .firstOrNull;
      if (match != null) {
        useBt = true;
        d.btAddress = match.address;
        d.btName = match.name;
        if (_name.text.trim().isEmpty || _name.text.startsWith('Computer '))
          _name.text = match.name;
      } else {
        note =
            'The PC (${info.bt}) is not paired with this phone. Pair it in Android Bluetooth '
            'settings, then scan again to add Bluetooth.';
      }
    }
    setState(() {
      d.useWifi = info.ip != null;
      d.useBt = useBt;
      _btNote = note ?? _btNote;
    });
    if (info.ip != null || useBt) await _connect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final wide = box.maxWidth >= 640;
                      final links = Column(
                        children: [
                          _wifiBlock(),
                          const SizedBox(height: 6),
                          _btBlock(),
                        ],
                      );
                      final actions = _actions();
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.editing == null
                                ? 'Add a computer'
                                : 'Edit computer',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (wide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: links),
                                const SizedBox(width: 24),
                                Expanded(child: actions),
                              ],
                            )
                          else ...[
                            links,
                            const SizedBox(height: 10),
                            actions,
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              left: 4,
              top: 4,
              child: IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wifiBlock() => Column(
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Wi-Fi'),
        subtitle: const Text('Same network as the PC'),
        value: d.useWifi,
        onChanged: _busy ? null : (v) => setState(() => d.useWifi = v),
      ),
      Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _host,
              enabled: d.useWifi && !_busy,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Desktop IP (127.0.0.1 for USB)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _port,
              enabled: d.useWifi && !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Port',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _btBlock() {
    final known = _devices.any((x) => x.address == d.btAddress);
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Bluetooth'),
          subtitle: const Text('The phone must be paired with the PC'),
          value: d.useBt,
          onChanged: _busy
              ? null
              : (v) {
                  setState(() => d.useBt = v);
                  if (v) _loadDevices();
                },
        ),
        if (d.useBt)
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: known ? d.btAddress : null,
                  hint: Text(d.btName.isNotEmpty ? d.btName : 'Choose your PC'),
                  items: [
                    for (final x in _devices)
                      DropdownMenuItem(
                        value: x.address,
                        child: Text('${x.name}  (${x.address})'),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (a) {
                          final x = _devices.firstWhere((x) => x.address == a);
                          setState(() {
                            d.btAddress = x.address;
                            d.btName = x.name;
                          });
                        },
                ),
              ),
              IconButton(
                tooltip: 'Refresh paired devices',
                icon: const Icon(Icons.refresh),
                onPressed: _busy ? null : _loadDevices,
              ),
            ],
          ),
        if (_btNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _btNote!,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _actions() => Column(
    children: [
      TextField(
        controller: _name,
        enabled: !_busy,
        decoration: const InputDecoration(
          isDense: true,
          labelText: 'Name (e.g. Laptop)',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _token,
        enabled: !_busy,
        decoration: const InputDecoration(
          isDense: true,
          labelText: 'Pairing token (shown by the agent)',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _busy ? null : _scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan QR code'),
      ),
      const SizedBox(height: 8),
      if (_busy)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            OutlinedButton(onPressed: _cancel, child: const Text('Cancel')),
          ],
        )
      else
        OutlinedButton(
          onPressed: _connect,
          child: Text(
            widget.editing == null ? 'Save & connect' : 'Save & reconnect',
          ),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      const SizedBox(height: 10),
      const Text(
        'Turn on both Wi-Fi and Bluetooth to switch between them without reconnecting. '
        'USB: run "adb reverse tcp:8765 tcp:8765" and use 127.0.0.1.',
        style: TextStyle(color: Colors.white38, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    ],
  );
}
