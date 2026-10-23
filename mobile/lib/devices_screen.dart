import 'package:flutter/material.dart';

import 'app_theme.dart';

import 'connection.dart';
import 'device_color.dart';
import 'device_form.dart';
import 'settings.dart';

void openDeviceForm(NavigatorState nav, [Device? editing]) => nav.push(
  MaterialPageRoute(builder: (_) => DeviceFormScreen(editing: editing)),
);

/// Shown while no computer is connected: your saved computers plus "Add".
class DeviceListScreen extends StatelessWidget {
  const DeviceListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Connection.instance;
    final s = Settings.instance;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListenableBuilder(
          listenable: Listenable.merge([c, s]),
          builder: (context, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Your computers',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (s.devices.length > 1)
                      TextButton(
                        onPressed: c.connectAll,
                        child: const Text('Connect all'),
                      ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => openDeviceForm(Navigator.of(context)),
                      icon: const Icon(Icons.add),
                      label: const Text('Add computer'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: s.devices.isEmpty
                      ? const Center(
                          child: Text(
                            'No computers yet.\nAdd one to start controlling it from this phone.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final d in s.devices)
                              DeviceRow(
                                device: d,
                                onTap: () => c.connectDevice(d.id),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Switch between connected computers (tap a row), or manage them.
class DevicesSheet extends StatelessWidget {
  const DevicesSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Connection.instance;
    final s = Settings.instance;
    final nav = Navigator.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([c, s]),
      builder: (context, _) {
        return _sheetBody(context, c, s, nav);
      },
    );
  }

  Widget _sheetBody(
    BuildContext context,
    Connection c,
    Settings s,
    NavigatorState nav,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Computers',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              if (s.devices.length > 1)
                TextButton(
                  onPressed: c.connectAll,
                  child: const Text('Connect all'),
                ),
              TextButton.icon(
                onPressed: () {
                  nav.pop();
                  openDeviceForm(nav);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          for (final d in s.devices)
            DeviceRow(
              device: d,
              inSheet: true,
              onTap: () {
                c.switchTo(d.id);
                nav.pop();
              },
            ),
          const SizedBox(height: 4),
          const Text(
            'Tap a computer to send input to it. Connected computers stay connected, '
            'so switching is instant.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class DeviceRow extends StatelessWidget {
  final Device device;
  final VoidCallback onTap;
  final bool inSheet;
  const DeviceRow({
    super.key,
    required this.device,
    required this.onTap,
    this.inSheet = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = Connection.instance;
    final s = c.session(device);
    final isActive = c.activeId == device.id && s.phase != Phase.idle;
    final connected = s.phase == Phase.active;

    final String status;
    if (connected) {
      final up = [
        if (s.usb.connected) Transport.usb.label,
        if (s.wifi.connected) Transport.wifi.label,
        if (s.bt.connected) Transport.bluetooth.label,
      ];
      // A link that should be up but is down is shown, so a fail-over is visible.
      final down = [
        // The cable is not "down" just because it is unplugged.
        for (final t in Transport.values)
          if (t != Transport.usb && s.wants(t) && !s.link(t).connected) t.label,
      ];
      status = up.isEmpty
          ? 'Connection lost - reconnecting...'
          : 'Connected - ${up.join(' + ')}'
                '${down.isEmpty ? '' : ' (${down.join(' + ')} down)'}';
    } else if (s.phase == Phase.connecting) {
      status = 'Connecting...';
    } else {
      final last = Settings.instance.lastActiveId == device.id
          ? ' (last used)'
          : '';
      status = (s.error ?? 'Not connected') + last;
    }

    final color = connected
        ? deviceColor(device.id)
        : s.phase == Phase.connecting
        ? Colors.orangeAccent
        : Colors.white38;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isActive ? context.desk.accentDim : context.desk.key,
      child: ListTile(
        onTap: onTap,
        leading: Icon(Icons.computer, color: color),
        title: Row(
          children: [
            Flexible(
              child: Text(device.title, overflow: TextOverflow.ellipsis),
            ),
            if (isActive && connected && inSheet)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Chip(
                  label: Text('Active', style: TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity(horizontal: -4, vertical: -4),
                  padding: EdgeInsets.zero,
                ),
              ),
          ],
        ),
        subtitle: Text(status, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            final nav = Navigator.of(context);
            switch (v) {
              case 'connect':
                await c.connectDevice(device.id);
              case 'disconnect':
                await c.disconnectDevice(device.id);
              case 'edit':
                if (inSheet) nav.pop();
                openDeviceForm(nav, device);
              case 'forget':
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text('Forget ${device.title}?'),
                    content: const Text(
                      'It will be disconnected and removed from this list.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Forget'),
                      ),
                    ],
                  ),
                );
                if (ok == true) await c.forgetDevice(device.id);
            }
          },
          itemBuilder: (_) => [
            if (s.phase == Phase.idle)
              const PopupMenuItem(value: 'connect', child: Text('Connect'))
            else
              const PopupMenuItem(
                value: 'disconnect',
                child: Text('Disconnect'),
              ),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(value: 'forget', child: Text('Forget')),
          ],
        ),
      ),
    );
  }
}
