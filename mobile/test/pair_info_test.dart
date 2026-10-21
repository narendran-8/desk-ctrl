import 'package:deskctrl/scan_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses wifi + bluetooth pairing QR', () {
    final p = PairInfo.parse(
      'deskctrl://pair/abcd1234?port=8765&ip=10.0.0.5&bt=aa:bb:cc:dd:ee:ff',
    )!;
    expect(p.token, 'abcd1234');
    expect(p.ip, '10.0.0.5');
    expect(p.port, 8765);
    expect(p.bt, 'AA:BB:CC:DD:EE:FF');
  });

  test('bluetooth-only QR (PC without network)', () {
    final p = PairInfo.parse(
      'deskctrl://pair/tok?port=8765&bt=AA:BB:CC:DD:EE:FF',
    )!;
    expect(p.ip, isNull);
    expect(p.bt, 'AA:BB:CC:DD:EE:FF');
  });

  test('rejects other content', () {
    expect(PairInfo.parse('https://example.com'), isNull);
    expect(
      PairInfo.parse('deskctrl://pair/tok?port=1'),
      isNull,
    ); // neither ip nor bt
    expect(PairInfo.parse('deskctrl://pair/?ip=1.2.3.4'), isNull); // no token
  });
}
