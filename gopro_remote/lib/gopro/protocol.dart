import 'dart:typed_data';

/// Open GoPro TLV command builders and response helpers (BLE).
///
/// Message format for short commands: `[length, id, ...payload]` where
/// `length` is the number of bytes that follow.
class GoProProtocol {
  GoProProtocol._();

  // Command IDs (CQ_COMMAND)
  static const int cmdSetShutter = 0x01;
  static const int cmdApControl = 0x17;
  static const int cmdSleep = 0x05;
  static const int cmdSetThirdPartyClientInfo = 0x50;

  // Query IDs (CQ_QUERY)
  static const int queryRegisterAllSettings = 0x52;
  static const int queryRegisterAllStatuses = 0x53;
  static const int queryGetStatusValues = 0x13;

  // Well-known status IDs (see Open GoPro statuses)
  static const int statusEncoding = 10;
  static const int statusEncodingDuration = 13;
  static const int statusWifiApEnabled = 69;
  static const int statusBatteryPercent = 70;

  static Uint8List setShutter({required bool on}) =>
      Uint8List.fromList([0x03, cmdSetShutter, 0x01, on ? 0x01 : 0x00]);

  static Uint8List setWifiAp({required bool on}) =>
      Uint8List.fromList([0x03, cmdApControl, 0x01, on ? 0x01 : 0x00]);

  static Uint8List setThirdPartyClientInfo() =>
      Uint8List.fromList([0x01, cmdSetThirdPartyClientInfo]);

  static Uint8List sleep() => Uint8List.fromList([0x01, cmdSleep]);

  static Uint8List registerAllSettings() =>
      Uint8List.fromList([0x01, queryRegisterAllSettings]);

  static Uint8List registerAllStatuses() =>
      Uint8List.fromList([0x01, queryRegisterAllStatuses]);

  /// Returns payload bytes after stripping the Open GoPro packet header.
  /// Continuation packets (bit7 set) return null for [expectedLength] and
  /// only the raw continuation body.
  static ({int? expectedLength, Uint8List body}) unpackPacket(Uint8List bytes) {
    if (bytes.isEmpty) {
      return (expectedLength: null, body: Uint8List(0));
    }

    final header = bytes[0];
    if ((header & 0x80) != 0) {
      // Continuation: drop the sequence nibble byte.
      return (expectedLength: null, body: bytes.sublist(1));
    }
    if ((header & 0x40) != 0) {
      // 16-bit extended length
      if (bytes.length < 3) {
        return (expectedLength: null, body: Uint8List(0));
      }
      final len = (bytes[1] << 8) | bytes[2];
      return (expectedLength: len, body: bytes.sublist(3));
    }
    if ((header & 0x20) != 0) {
      // 13-bit extended length
      if (bytes.length < 2) {
        return (expectedLength: null, body: Uint8List(0));
      }
      final len = ((header & 0x0F) << 8) | bytes[1];
      return (expectedLength: len, body: bytes.sublist(2));
    }
    // 8-bit length
    return (expectedLength: header, body: bytes.sublist(1));
  }

  /// Parse status TLV list: `[id, len, ...value bytes]` repeated.
  static Map<int, Uint8List> parseStatusTlvs(Uint8List payload) {
    final out = <int, Uint8List>{};
    var i = 0;
    // Skip leading command id + status byte when present (e.g. 0x53, 0x00).
    if (payload.length >= 2 &&
        (payload[0] == queryRegisterAllStatuses ||
            payload[0] == queryGetStatusValues ||
            payload[0] == 0x93)) {
      i = 2;
    }
    while (i + 1 < payload.length) {
      final id = payload[i];
      final len = payload[i + 1];
      i += 2;
      if (i + len > payload.length) break;
      out[id] = Uint8List.fromList(payload.sublist(i, i + len));
      i += len;
    }
    return out;
  }

  static int? readUint(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    var v = 0;
    for (final b in bytes) {
      v = (v << 8) | b;
    }
    return v;
  }
}
