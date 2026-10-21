import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Parsed contents of a `deskctrl://pair/TOKEN?ip=..&port=..&bt=..` QR code.
/// Everything except the token is optional (a PC without network can still pair over Bluetooth).
class PairInfo {
  final String? ip;
  final int port;
  final String token;
  final String? bt;

  /// `usb=1`: sent by the agent over the USB cable. Carries only the token and the port.
  final bool usb;
  final String? name;

  /// The computer's own id (see [Device.computerId]).
  final String? computerId;
  const PairInfo({
    this.ip,
    required this.port,
    required this.token,
    this.bt,
    this.usb = false,
    this.name,
    this.computerId,
  });

  static PairInfo? parse(String raw) {
    final u = Uri.tryParse(raw.trim());
    if (u == null || u.scheme != 'deskctrl' || u.pathSegments.isEmpty)
      return null;
    final token = u.pathSegments.first;
    final ip = u.queryParameters['ip'];
    final bt = u.queryParameters['bt'];
    final usb = u.queryParameters['usb'] == '1';
    if (token.isEmpty || (ip == null && bt == null && !usb)) return null;
    return PairInfo(
      usb: usb,
      name: u.queryParameters['name'],
      computerId: u.queryParameters['id'],
      ip: ip,
      port: int.tryParse(u.queryParameters['port'] ?? '') ?? 8765,
      token: token,
      bt: bt?.toUpperCase(),
    );
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _done = false;

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final info = PairInfo.parse(b.rawValue ?? '');
      if (info != null) {
        _done = true;
        Navigator.of(context).pop(info);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MobileScanner(
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable (${error.errorCode.name}).\n'
                  'Allow camera permission or enter the details manually.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Point at the QR code in the desktop agent'),
            ),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
