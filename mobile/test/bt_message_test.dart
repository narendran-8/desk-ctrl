import 'package:deskctrl/links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a failed Bluetooth connection says what to check and keeps the real reason', () {
    const raw = 'read failed, socket might closed or timeout, read ret: -1';
    final m = BtLink.friendly(raw);
    expect(m, contains('agent is running'));
    expect(m, contains('paired'));
    expect(m, contains(raw), reason: 'the system message is not hidden');
    expect(
      BtLink.friendly('Service discovery failed'),
      contains('Service discovery failed'),
    );
  });

  test('other messages pass through unchanged', () {
    expect(
      BtLink.friendly('Bluetooth is turned off'),
      'Bluetooth is turned off',
    );
    expect(BtLink.friendly('Timed out connecting'), 'Timed out connecting');
  });
}
