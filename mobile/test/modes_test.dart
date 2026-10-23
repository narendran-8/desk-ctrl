import 'package:deskctrl/modes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tabs follow the Settings switches, the keyboard is always there', () {
    expect(availableModes(mouse: true, pad: true), [
      Mode.keyboard,
      Mode.mouse,
      Mode.pad,
    ]);
    expect(availableModes(mouse: false, pad: true), [Mode.keyboard, Mode.pad]);
    expect(availableModes(mouse: true, pad: false), [
      Mode.keyboard,
      Mode.mouse,
    ]);
    expect(availableModes(mouse: false, pad: false), [Mode.keyboard]);
  });

  test('the order is the user\'s order', () {
    const order = [Mode.mouse, Mode.keyboard, Mode.pad];
    expect(availableModes(mouse: true, pad: true, order: order), order);
    expect(availableModes(mouse: false, pad: true, order: order), [
      Mode.keyboard,
      Mode.pad,
    ]);
    expect(availableModes(mouse: true, pad: true, voice: true, mobile: true), [
      Mode.keyboard,
      Mode.mouse,
      Mode.pad,
      Mode.voice,
      Mode.mobile,
    ]);
    expect(
      availableModes(mouse: true, pad: true, voice: true, mobile: false),
      isNot(contains(Mode.mobile)),
    );
  });

  test('a mode missing from a saved order is not lost', () {
    expect(completeOrder([Mode.pad]), [
      Mode.pad,
      Mode.keyboard,
      Mode.mouse,
      Mode.voice,
      Mode.mobile,
    ]);
    expect(completeOrder(parseModeOrder(['mouse', 'nonsense'])), [
      Mode.mouse,
      Mode.keyboard,
      Mode.pad,
      Mode.voice,
      Mode.mobile,
    ]);
  });

  test('a tap cycles through the modes and wraps around', () {
    const modes = [Mode.keyboard, Mode.pad, Mode.mouse];
    expect(
      nextMode(modes, Mode.keyboard),
      Mode.pad,
      reason: 'keyboard -> trackpad',
    );
    expect(nextMode(modes, Mode.pad), Mode.mouse);
    expect(nextMode(modes, Mode.mouse), Mode.keyboard);
    expect(nextMode([Mode.keyboard, Mode.mouse], Mode.keyboard), Mode.mouse);
    expect(nextMode(modes, Mode.pad), isNot(Mode.pad));
  });
}
