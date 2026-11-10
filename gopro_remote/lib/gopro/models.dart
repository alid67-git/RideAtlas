import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum GoProConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

/// Thrown when the user aborts a long BLE operation (scan / connect / wake).
class GoProCancelledException implements Exception {
  const GoProCancelledException();

  @override
  String toString() => 'İptal edildi';
}

/// Persisted camera the user can select / forget from the devices menu.
class SavedGoProDevice {
  const SavedGoProDevice({
    required this.remoteId,
    required this.name,
    required this.addedAtMs,
  });

  final String remoteId;
  final String name;
  final int addedAtMs;

  SavedGoProDevice copyWith({String? name}) {
    return SavedGoProDevice(
      remoteId: remoteId,
      name: name ?? this.name,
      addedAtMs: addedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'remoteId': remoteId,
        'name': name,
        'addedAtMs': addedAtMs,
      };

  factory SavedGoProDevice.fromJson(Map<String, dynamic> json) {
    return SavedGoProDevice(
      remoteId: json['remoteId'] as String? ?? '',
      name: json['name'] as String? ?? 'GoPro',
      addedAtMs: (json['addedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class GoProDeviceInfo {
  const GoProDeviceInfo({
    required this.device,
    required this.name,
    required this.remoteId,
    this.rssi,
  });

  final BluetoothDevice device;
  final String name;
  final String remoteId;
  final int? rssi;

  /// Last 4 of serial / default SSID suffix when name is like "GoPro 1234".
  String? get serialSuffix {
    final match = RegExp(r'GoPro\s+([A-Z0-9]{4})$', caseSensitive: false)
        .firstMatch(name);
    return match?.group(1)?.toUpperCase();
  }

  /// Rough model hint from advertised name patterns. Open GoPro covers
  /// HERO10–13 Black (and newer) when firmware is recent enough.
  String get modelHint {
    final lower = name.toLowerCase();
    if (lower.contains('hero13') || lower.contains('h13')) return 'HERO13';
    if (lower.contains('hero12') || lower.contains('h12')) return 'HERO12';
    if (lower.contains('hero11') || lower.contains('h11')) return 'HERO11';
    if (lower.contains('hero10') || lower.contains('h10')) return 'HERO10';
    return 'GoPro (Open GoPro)';
  }
}

class GoProCameraStatus {
  const GoProCameraStatus({
    this.encoding = false,
    this.encodingDurationSec,
    this.batteryPercent,
    this.wifiApEnabled = false,
    this.wifiSsid,
    this.wifiPassword,
  });

  final bool encoding;
  final int? encodingDurationSec;
  final int? batteryPercent;
  final bool wifiApEnabled;
  final String? wifiSsid;
  final String? wifiPassword;

  GoProCameraStatus copyWith({
    bool? encoding,
    int? encodingDurationSec,
    int? batteryPercent,
    bool? wifiApEnabled,
    String? wifiSsid,
    String? wifiPassword,
  }) {
    return GoProCameraStatus(
      encoding: encoding ?? this.encoding,
      encodingDurationSec: encodingDurationSec ?? this.encodingDurationSec,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      wifiApEnabled: wifiApEnabled ?? this.wifiApEnabled,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      wifiPassword: wifiPassword ?? this.wifiPassword,
    );
  }
}
