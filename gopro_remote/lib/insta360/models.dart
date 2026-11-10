enum Insta360ConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  unsupported,
}

class Insta360CameraStatus {
  const Insta360CameraStatus({
    this.encoding = false,
    this.encodingDurationSec,
    this.batteryPercent,
  });

  final bool encoding;
  final int? encodingDurationSec;
  final int? batteryPercent;

  Insta360CameraStatus copyWith({
    bool? encoding,
    int? encodingDurationSec,
    int? batteryPercent,
  }) {
    return Insta360CameraStatus(
      encoding: encoding ?? this.encoding,
      encodingDurationSec: encodingDurationSec ?? this.encodingDurationSec,
      batteryPercent: batteryPercent ?? this.batteryPercent,
    );
  }
}
