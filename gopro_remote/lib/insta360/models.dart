enum Insta360ConnectionState {
  disconnected,
  advertising,
  connecting,
  connected,
  error,
}

/// Thrown when the user aborts a long Insta360 operation.
class Insta360CancelledException implements Exception {
  const Insta360CancelledException();

  @override
  String toString() => 'İptal edildi';
}

class Insta360CameraStatus {
  const Insta360CameraStatus({
    this.encoding = false,
    this.encodingDurationSec,
    this.batteryPercent,
    this.displayText,
  });

  final bool encoding;
  final int? encodingDurationSec;
  final int? batteryPercent;
  final String? displayText;

  Insta360CameraStatus copyWith({
    bool? encoding,
    int? encodingDurationSec,
    int? batteryPercent,
    String? displayText,
  }) {
    return Insta360CameraStatus(
      encoding: encoding ?? this.encoding,
      encodingDurationSec: encodingDurationSec ?? this.encodingDurationSec,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      displayText: displayText ?? this.displayText,
    );
  }
}

/// Persisted Insta360 camera (wake serial is required for sleep→wake).
class SavedInsta360Device {
  const SavedInsta360Device({
    required this.serial,
    required this.name,
    required this.addedAtMs,
    this.remoteId,
  });

  /// 6-character ORBIT wake serial (e.g. `34UQG5`).
  final String serial;
  final String name;
  final int addedAtMs;

  /// Optional BLE address when discovered while the camera was awake.
  final String? remoteId;

  SavedInsta360Device copyWith({String? name, String? remoteId}) {
    return SavedInsta360Device(
      serial: serial,
      name: name ?? this.name,
      addedAtMs: addedAtMs,
      remoteId: remoteId ?? this.remoteId,
    );
  }

  Map<String, dynamic> toJson() => {
        'serial': serial,
        'name': name,
        'addedAtMs': addedAtMs,
        'remoteId': remoteId,
      };

  factory SavedInsta360Device.fromJson(Map<String, dynamic> json) {
    return SavedInsta360Device(
      serial: (json['serial'] as String? ?? '').toUpperCase(),
      name: json['name'] as String? ?? 'Insta360',
      addedAtMs: (json['addedAtMs'] as num?)?.toInt() ?? 0,
      remoteId: json['remoteId'] as String?,
    );
  }
}

class Insta360ScanHit {
  const Insta360ScanHit({
    required this.name,
    required this.remoteId,
    required this.serial,
    this.rssi,
  });

  final String name;
  final String remoteId;
  final String serial;
  final int? rssi;
}
