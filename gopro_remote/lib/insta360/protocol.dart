import 'dart:convert';
import 'dart:typed_data';

/// Button codes for GPS-remote `ce82` frames (remote → camera).
class InstaButton {
  static const power = 0x00;
  static const mode = 0x01;
  static const shutter = 0x02;
}

class InstaButtonState {
  static const click = 0x00;
  static const held = 0x03;
}

/// Extract the 6-character wake serial from a camera BLE name or raw serial.
///
/// Examples: `X4 34UQG5`, `Insta360 X4 34UQG5`, `34UQG5`.
String? extractInstaSerial(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return null;

  final prefixed = RegExp(
    r'^(?:Insta360\s+)?'
    r'(?:X3|X4|X5|ONE\s*X2|ONE\s*X3|ONE\s*RS|Ace\s*Pro|GO\s*3S?|GO\s*2)'
    r'\s+([A-Za-z0-9]{6})$',
    caseSensitive: false,
  ).firstMatch(name);
  if (prefixed != null) {
    return prefixed.group(1)!.toUpperCase();
  }

  final bare = RegExp(r'^([A-Za-z0-9]{6})$').firstMatch(name);
  if (bare != null) return bare.group(1)!.toUpperCase();

  // Fallback: trailing 6 alnum tokens after whitespace.
  final trailing = RegExp(r'([A-Za-z0-9]{6})\s*$').firstMatch(name);
  return trailing?.group(1)?.toUpperCase();
}

bool looksLikeInsta360Name(String name) {
  final lower = name.toLowerCase();
  return lower.contains('x3') ||
      lower.contains('x4') ||
      lower.contains('x5') ||
      lower.contains('one x') ||
      lower.contains('one rs') ||
      lower.contains('ace pro') ||
      lower.contains('go 3') ||
      lower.contains('go 2') ||
      lower.contains('insta360');
}

/// Manufacturer payload (without company ID) for the ORBIT wake beacon.
///
/// Confirmed against X4 captures: Apple iBeacon envelope + ASCII serial.
Uint8List buildOrbitWakeManufacturerData(String serial6) {
  final serial = extractInstaSerial(serial6) ?? serial6.trim().toUpperCase();
  if (serial.length != 6) {
    throw ArgumentError('Insta360 wake serial must be 6 characters, got "$serial"');
  }
  final bytes = Uint8List(24);
  // iBeacon prefix
  bytes[0] = 0x02;
  bytes[1] = 0x15;
  // "ORBIT" framing
  bytes[2] = 0x09;
  bytes.setRange(3, 8, ascii.encode('ORBIT'));
  bytes[8] = 0x09;
  bytes[9] = 0xff;
  bytes[10] = 0x0f;
  bytes[11] = 0x00;
  // Camera serial ASCII
  bytes.setRange(12, 18, ascii.encode(serial));
  // major/minor/txpower (X4-confirmed)
  bytes[18] = 0x00;
  bytes[19] = 0x00;
  bytes[20] = 0x00;
  bytes[21] = 0x00;
  bytes[22] = 0xe4;
  bytes[23] = 0x01;
  return bytes;
}

/// `FC EF FE 86 <sn> 03 01 <btn> <state>`
Uint8List buildButtonFrame({
  required int sequence,
  required int button,
  required int state,
}) {
  return Uint8List.fromList([
    0xfc,
    0xef,
    0xfe,
    0x86,
    sequence & 0xff,
    0x03,
    0x01,
    button & 0xff,
    state & 0xff,
  ]);
}

Uint8List shutterClickFrame(int sequence) => buildButtonFrame(
      sequence: sequence,
      button: InstaButton.shutter,
      state: InstaButtonState.click,
    );

Uint8List powerClickFrame(int sequence) => buildButtonFrame(
      sequence: sequence,
      button: InstaButton.power,
      state: InstaButtonState.click,
    );

Uint8List powerHoldFrame(int sequence) => buildButtonFrame(
      sequence: sequence,
      button: InstaButton.power,
      state: InstaButtonState.held,
    );

/// Parse camera→remote `ce81` status frames for recording timer / battery hints.
InstaParsedCameraWrite? parseCameraWrite(Uint8List data) {
  if (data.length < 6) return null;
  if (data[0] != 0xfe || data[1] != 0xef || data[2] != 0xfe) return null;
  final type = data[3];
  final len = data[5];
  final payloadStart = 6;
  if (payloadStart + len > data.length && type != 0x10) {
    // Some 0x10 frames include control bytes before ASCII; fall through.
  }

  if (type == 0x07) {
    // Serial handshake: FE EF FE 07 00 06 <serial>
    if (data.length >= 12) {
      final serial = ascii.decode(data.sublist(6, 12), allowInvalid: true);
      return InstaParsedCameraWrite(serial: serial.toUpperCase());
    }
  }

  if (type == 0x10) {
    // Display string — find printable ASCII tail.
    final asciiBytes = <int>[];
    for (var i = 6; i < data.length; i++) {
      final b = data[i];
      if (b >= 0x20 && b <= 0x7e) {
        asciiBytes.add(b);
      }
    }
    if (asciiBytes.isEmpty) return null;
    final text = ascii.decode(asciiBytes).trim();
    final timer = RegExp(r'\.?(\d{2}):(\d{2}):(\d{2})$').firstMatch(text);
    if (timer != null) {
      final h = int.parse(timer.group(1)!);
      final m = int.parse(timer.group(2)!);
      final s = int.parse(timer.group(3)!);
      return InstaParsedCameraWrite(
        displayText: text,
        encoding: true,
        encodingDurationSec: h * 3600 + m * 60 + s,
      );
    }
    final batt = RegExp(r'(\d+)\s*h\s*(\d+)\s*m', caseSensitive: false)
        .firstMatch(text);
    return InstaParsedCameraWrite(
      displayText: text,
      encoding: false,
      batteryHint: batt != null ? text : null,
    );
  }

  return InstaParsedCameraWrite(rawType: type);
}

class InstaParsedCameraWrite {
  const InstaParsedCameraWrite({
    this.serial,
    this.displayText,
    this.encoding,
    this.encodingDurationSec,
    this.batteryHint,
    this.rawType,
  });

  final String? serial;
  final String? displayText;
  final bool? encoding;
  final int? encodingDurationSec;
  final String? batteryHint;
  final int? rawType;
}
