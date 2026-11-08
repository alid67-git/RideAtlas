/// Open GoPro BLE UUIDs.
///
/// Short form `GP-XXXX` expands to `b5f9XXXX-aa8d-11e3-9046-0002a5d5c51b`.
class GoProUuids {
  GoProUuids._();

  static const String base = 'b5f9{}-aa8d-11e3-9046-0002a5d5c51b';

  static String gp(String fourHex) =>
      base.replaceFirst('{}', fourHex.toLowerCase());

  /// Control & Query service (16-bit FEA6).
  static const String controlService = '0000fea6-0000-1000-8000-00805f9b34fb';

  static final String wifiApSsid = gp('0002');
  static final String wifiApPassword = gp('0003');

  static final String commandReq = gp('0072');
  static final String commandRsp = gp('0073');
  static final String settingsReq = gp('0074');
  static final String settingsRsp = gp('0075');
  static final String queryReq = gp('0076');
  static final String queryRsp = gp('0077');
}
