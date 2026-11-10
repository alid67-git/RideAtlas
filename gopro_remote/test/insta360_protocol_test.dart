import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gopro_remote/insta360/protocol.dart';

void main() {
  group('extractInstaSerial', () {
    test('parses X4 name and bare serial', () {
      expect(extractInstaSerial('X4 34UQG5'), '34UQG5');
      expect(extractInstaSerial('Insta360 X4 34UQG5'), '34UQG5');
      expect(extractInstaSerial('34UQG5'), '34UQG5');
      expect(extractInstaSerial('x3 abcdef'), 'ABCDEF');
    });

    test('rejects junk', () {
      expect(extractInstaSerial(''), isNull);
      expect(extractInstaSerial('GoPro 1234'), isNull);
    });
  });

  test('ORBIT wake manufacturer payload embeds ASCII serial', () {
    final data = buildOrbitWakeManufacturerData('34UQG5');
    expect(data.length, 24);
    expect(data[0], 0x02);
    expect(data[1], 0x15);
    expect(ascii.decode(data.sublist(3, 8)), 'ORBIT');
    expect(ascii.decode(data.sublist(12, 18)), '34UQG5');
    expect(data[22], 0xe4);
    expect(data[23], 0x01);
  });

  test('button frames match GPS remote layout', () {
    final shutter = shutterClickFrame(0);
    expect(
      shutter,
      [0xfc, 0xef, 0xfe, 0x86, 0x00, 0x03, 0x01, 0x02, 0x00],
    );
    final hold = powerHoldFrame(2);
    expect(
      hold,
      [0xfc, 0xef, 0xfe, 0x86, 0x02, 0x03, 0x01, 0x00, 0x03],
    );
  });

  test('parseCameraWrite detects recording timer', () {
    final frame = Uint8List.fromList([
      0xfe, 0xef, 0xfe, 0x10, 0x80, 0x0d, 0x01, 0x0e, 0x46, 0x01,
      ...ascii.encode('.00:00:05'),
    ]);
    final parsed = parseCameraWrite(frame);
    expect(parsed?.encoding, isTrue);
    expect(parsed?.encodingDurationSec, 5);
  });
}
