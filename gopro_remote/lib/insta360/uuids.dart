/// Insta360 GPS Remote GATT layout (Architecture A — phone is peripheral).
class InstaUuids {
  InstaUuids._();

  static const serviceCe80 = '0000ce80-0000-1000-8000-00805f9b34fb';
  static const charCe81 = '0000ce81-0000-1000-8000-00805f9b34fb'; // camera → remote writes
  static const charCe82 = '0000ce82-0000-1000-8000-00805f9b34fb'; // remote → camera notify
  static const charCe83 = '0000ce83-0000-1000-8000-00805f9b34fb'; // remote info read

  /// Secondary identity service seen on the official GPS Remote / ESP32 ports.
  static const serviceD0ff = '0000d0ff-3c17-d293-8e48-14fe2e4da212';
  static const charFfd1 = '0000ffd1-0000-1000-8000-00805f9b34fb';
  static const charFfd2 = '0000ffd2-0000-1000-8000-00805f9b34fb';
  static const charFfd3 = '0000ffd3-0000-1000-8000-00805f9b34fb';
  static const charFfd4 = '0000ffd4-0000-1000-8000-00805f9b34fb';

  /// Apple company ID used by the ORBIT wake “iBeacon” envelope.
  static const appleCompanyId = 0x004C;
}
