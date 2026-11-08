import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gopro_remote/gopro/protocol.dart';

void main() {
  test('setShutter payloads match Open GoPro tutorials', () {
    expect(
      GoProProtocol.setShutter(on: true),
      Uint8List.fromList([0x03, 0x01, 0x01, 0x01]),
    );
    expect(
      GoProProtocol.setShutter(on: false),
      Uint8List.fromList([0x03, 0x01, 0x01, 0x00]),
    );
  });

  test('wifi AP and third-party init bytes', () {
    expect(
      GoProProtocol.setWifiAp(on: true),
      Uint8List.fromList([0x03, 0x17, 0x01, 0x01]),
    );
    expect(
      GoProProtocol.setThirdPartyClientInfo(),
      Uint8List.fromList([0x01, 0x50]),
    );
    expect(
      GoProProtocol.registerAllStatuses(),
      Uint8List.fromList([0x01, 0x53]),
    );
  });

  test('unpack short packet and parse status TLVs', () {
    final unpacked = GoProProtocol.unpackPacket(
      Uint8List.fromList([0x08, 0x53, 0x00, 0x0A, 0x01, 0x01, 0x46, 0x01, 0x55]),
    );
    expect(unpacked.expectedLength, 8);
    final map = GoProProtocol.parseStatusTlvs(unpacked.body);
    expect(GoProProtocol.readUint(map[10]), 1);
    expect(GoProProtocol.readUint(map[70]), 0x55);
  });
}
