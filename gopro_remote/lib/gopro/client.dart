import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'models.dart';
import 'protocol.dart';
import 'uuids.dart';

/// BLE remote for GoPro HERO10–13 Black (Open GoPro).
///
/// Shutter start/stop works over BLE alone — no phone↔camera Wi‑Fi required
/// for record control. Wi‑Fi AP credentials are still readable for later
/// media / preview work.
class GoProBleClient extends ChangeNotifier {
  GoProConnectionState _state = GoProConnectionState.disconnected;
  GoProConnectionState get state => _state;

  String? _error;
  String? get error => _error;

  final List<GoProDeviceInfo> discovered = [];
  GoProDeviceInfo? connectedDevice;
  GoProCameraStatus status = const GoProCameraStatus();

  BluetoothDevice? _device;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  final List<StreamSubscription<List<int>>> _notifySubs = [];

  BluetoothCharacteristic? _commandReq;
  BluetoothCharacteristic? _queryReq;
  BluetoothCharacteristic? _wifiSsid;
  BluetoothCharacteristic? _wifiPassword;

  final _cmdBuf = BytesBuilder(copy: false);
  int _cmdExpected = 0;
  final _queryBuf = BytesBuilder(copy: false);
  int _queryExpected = 0;

  Completer<bool>? _pendingCommand;

  bool _autoConnectInFlight = false;
  Completer<GoProDeviceInfo>? _firstDeviceCompleter;

  /// Local session flag — encoding status notifications can lag or miss,
  /// so the single record button must not rely only on [status.encoding].
  bool _sessionRecording = false;
  bool get isSessionRecording => _sessionRecording || status.encoding;

  bool get isConnected =>
      _state == GoProConnectionState.connected && _device != null;

  Future<void> ensureAdapterOn() async {
    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      throw StateError('Bu cihaz BLE desteklemiyor.');
    }
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 15));
    }
  }

  /// Scan, then automatically connect to the strongest GoPro found.
  Future<void> autoConnect({
    Duration scanTimeout = const Duration(seconds: 15),
    int connectRetries = 5,
  }) async {
    if (isConnected || _autoConnectInFlight) return;
    _autoConnectInFlight = true;
    _error = null;
    notifyListeners();

    try {
      await ensureAdapterOn();
      await startScan(
        timeout: scanTimeout,
        autoConnectFirst: true,
      );

      final target = discovered.isNotEmpty
          ? discovered.first
          : await (_firstDeviceCompleter?.future ??
                Future<GoProDeviceInfo>.error(
                  StateError('GoPro bulunamadı. Kamerayı açıp tekrar dene.'),
                ));

      await connect(target, retries: connectRetries);
    } finally {
      _autoConnectInFlight = false;
      notifyListeners();
    }
  }

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 12),
    bool autoConnectFirst = false,
  }) async {
    _error = null;
    discovered.clear();
    _firstDeviceCompleter = Completer<GoProDeviceInfo>();
    _setState(GoProConnectionState.scanning);

    await ensureAdapterOn();
    await _scanSub?.cancel();

    // Flush stale results from a previous scan.
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName;
        if (name.isEmpty) continue;
        if (!_looksLikeGoPro(name)) continue;
        final id = r.device.remoteId.str;
        final existing = discovered.indexWhere((d) => d.remoteId == id);
        final info = GoProDeviceInfo(
          device: r.device,
          name: name,
          remoteId: id,
          rssi: r.rssi,
        );
        if (existing >= 0) {
          discovered[existing] = info;
        } else {
          discovered.add(info);
          final pending = _firstDeviceCompleter;
          if (pending != null && !pending.isCompleted) {
            pending.complete(info);
          }
        }
      }
      discovered.sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
      notifyListeners();
    });

    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: true,
      // Continuous updates help auto-connect as soon as the camera appears.
      continuousUpdates: true,
    );

    // Wait until first camera or scan ends.
    if (autoConnectFirst) {
      try {
        await _firstDeviceCompleter!.future.timeout(timeout);
      } on TimeoutException {
        // fall through — caller handles empty list
      }
    } else {
      // startScan returns when timeout ends for non-auto mode.
    }

    if (_state == GoProConnectionState.scanning && !_autoConnectInFlight) {
      _setState(GoProConnectionState.disconnected);
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    if (_state == GoProConnectionState.scanning) {
      _setState(GoProConnectionState.disconnected);
    }
  }

  Future<void> connect(
    GoProDeviceInfo info, {
    int retries = 5,
  }) async {
    _error = null;
    await stopScan();
    // Android GATT 133 is common if we connect immediately after stopScan.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _setState(GoProConnectionState.connecting);

    Object? lastError;
    for (var attempt = 1; attempt <= retries; attempt++) {
      try {
        await _connectOnce(info, attempt: attempt);
        connectedDevice = info;
        _error = null;
        _setState(GoProConnectionState.connected);
        return;
      } catch (e) {
        lastError = e;
        debugPrint('GoPro connect attempt $attempt/$retries failed: $e');
        await _teardownLink(keepState: true);
        // Progressive backoff — helps clear Android GATT 133.
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }

    _error = _friendlyError(lastError);
    _setState(GoProConnectionState.error);
    throw StateError(_error!);
  }

  Future<void> _connectOnce(GoProDeviceInfo info, {required int attempt}) async {
    final device = info.device;
    _device = device;

    // Always force a clean disconnect before connect (Android 133 mitigation).
    try {
      await device.disconnect();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 250));

    if (attempt >= 3) {
      try {
        await device.clearGattCache();
      } catch (_) {}
    }

    await device.connect(
      timeout: const Duration(seconds: 25),
      autoConnect: false,
      mtu: null, // negotiate after connect; avoids some OEM 133 races
    );

    // Wait until Android reports connected.
    await device.connectionState
        .firstWhere((s) => s == BluetoothConnectionState.connected)
        .timeout(const Duration(seconds: 20));

    // Pairing is required by Open GoPro before most commands succeed.
    // Skip createBond if already bonded to avoid extra 133s.
    try {
      final bond = await device.bondState
          .first
          .timeout(const Duration(seconds: 2), onTimeout: () => BluetoothBondState.none);
      if (bond != BluetoothBondState.bonded) {
        await device.createBond(timeout: 45);
      }
    } catch (e) {
      debugPrint('Bond/pair note: $e');
    }

    await _connSub?.cancel();
    _connSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected &&
          _state == GoProConnectionState.connected) {
        _error = 'Bağlantı koptu';
        connectedDevice = null;
        _setState(GoProConnectionState.disconnected);
      }
    });

    try {
      await device.requestMtu(512);
    } catch (_) {}

    await device.discoverServices();
    await _bindCharacteristics(device);
    await _enableNotifications(device);

    // Open GoPro init sequence (mirrors official C# / Python demos).
    await _writeCommand(GoProProtocol.setThirdPartyClientInfo(), wait: false);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _writeQuery(GoProProtocol.registerAllSettings(), wait: false);
    await _writeQuery(GoProProtocol.registerAllStatuses(), wait: false);
    // Wi‑Fi AP credentials are optional (media download later); not needed
    // for BLE shutter control, so we skip reading them on every connect.
  }

  Future<void> disconnect() async {
    await stopScan();
    await _teardownLink();
    connectedDevice = null;
    status = const GoProCameraStatus();
    _setState(GoProConnectionState.disconnected);
  }

  Future<void> startRecording() async {
    await _writeCommand(GoProProtocol.setShutter(on: true));
    _sessionRecording = true;
    status = status.copyWith(encoding: true);
    notifyListeners();
  }

  Future<void> stopRecording() async {
    await _writeCommand(GoProProtocol.setShutter(on: false));
    _sessionRecording = false;
  }

  Future<void> setWifiAp(bool on) =>
      _writeCommand(GoProProtocol.setWifiAp(on: on));

  /// Sleep / power-down without waiting for a BLE notify — the camera often
  /// drops the link before a response arrives, which used to look like failure.
  Future<void> sleepCamera() async {
    await _fireAndForgetCommand(GoProProtocol.sleep());
  }

  Future<void> powerDownCamera() async {
    await _fireAndForgetCommand(GoProProtocol.powerDown());
  }

  Future<void> _fireAndForgetCommand(Uint8List bytes) async {
    final char = _commandReq;
    if (char == null) throw StateError('Bağlı değil');
    try {
      // Write Command (no ATT response) — survives the camera going away.
      await char.write(bytes, withoutResponse: true);
    } catch (e) {
      debugPrint('fire-and-forget write: $e');
      try {
        await char.write(bytes, withoutResponse: false);
      } catch (e2) {
        debugPrint('fallback write: $e2');
      }
    }
  }

  Future<void> _waitUntilNotEncoding({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (status.encoding && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    // Brief settle even if status never flipped (some FW skip the notify).
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  /// Single control: start = ensure BLE + shutter on;
  /// stop = shutter off, wait for encode end, then sleep (+ power-down fallback).
  Future<void> toggleRecording() async {
    if (isSessionRecording) {
      try {
        await stopRecording();
      } catch (e) {
        debugPrint('stopRecording: $e');
        _sessionRecording = false;
      }

      await _waitUntilNotEncoding();

      // Camera rejects sleep while still busy; after encode settles, sleep
      // then force power-down as a second shot for stubborn firmware.
      try {
        await sleepCamera();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (_commandReq != null) {
          await powerDownCamera();
        }
      } catch (e) {
        debugPrint('Sleep/power-down after stop: $e');
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _teardownLink();
      connectedDevice = null;
      _sessionRecording = false;
      status = const GoProCameraStatus();
      _setState(GoProConnectionState.disconnected);
      return;
    }

    if (!isConnected) {
      await autoConnect();
    }
    await startRecording();
  }

  Future<void> refreshWifiCredentials() async {
    final ssidChar = _wifiSsid;
    final passChar = _wifiPassword;
    if (ssidChar == null || passChar == null) return;

    final ssidBytes = await ssidChar.read();
    final passBytes = await passChar.read();
    final ssid = String.fromCharCodes(ssidBytes).trim();
    final password = String.fromCharCodes(passBytes).trim();
    status = status.copyWith(
      wifiSsid: ssid.isEmpty ? null : ssid,
      wifiPassword: password.isEmpty ? null : password,
    );
    notifyListeners();
  }

  Future<void> _bindCharacteristics(BluetoothDevice device) async {
    _commandReq = null;
    _queryReq = null;
    _wifiSsid = null;
    _wifiPassword = null;

    for (final service in device.servicesList) {
      for (final c in service.characteristics) {
        final u = c.uuid.str128.toLowerCase();
        if (u == GoProUuids.commandReq) _commandReq = c;
        if (u == GoProUuids.queryReq) _queryReq = c;
        if (u == GoProUuids.wifiApSsid) _wifiSsid = c;
        if (u == GoProUuids.wifiApPassword) _wifiPassword = c;
      }
    }

    if (_commandReq == null) {
      throw StateError(
        'GoPro komut karakteristiği bulunamadı. Kamerayı '
        'eşleştirme moduna alıp tekrar dene (HERO10–13, güncel FW).',
      );
    }
  }

  Future<void> _enableNotifications(BluetoothDevice device) async {
    for (final sub in _notifySubs) {
      await sub.cancel();
    }
    _notifySubs.clear();

    for (final service in device.servicesList) {
      for (final c in service.characteristics) {
        if (!c.properties.notify && !c.properties.indicate) continue;
        final u = c.uuid.str128.toLowerCase();
        await c.setNotifyValue(true);
        final sub = c.onValueReceived.listen((value) {
          _onNotify(u, Uint8List.fromList(value));
        });
        _notifySubs.add(sub);
      }
    }
  }

  void _onNotify(String uuid, Uint8List value) {
    if (uuid == GoProUuids.commandRsp) {
      _accumulate(
        value,
        buf: _cmdBuf,
        expected: () => _cmdExpected,
        setExpected: (v) => _cmdExpected = v,
        onComplete: (payload) {
          final ok = payload.length >= 2 && payload[1] == 0x00;
          final pending = _pendingCommand;
          if (pending != null && !pending.isCompleted) {
            pending.complete(ok);
          }
        },
      );
      return;
    }

    if (uuid == GoProUuids.queryRsp) {
      _accumulate(
        value,
        buf: _queryBuf,
        expected: () => _queryExpected,
        setExpected: (v) => _queryExpected = v,
        onComplete: _applyStatusPayload,
      );
    }
  }

  void _accumulate(
    Uint8List packet, {
    required BytesBuilder buf,
    required int Function() expected,
    required void Function(int) setExpected,
    required void Function(Uint8List payload) onComplete,
  }) {
    final unpacked = GoProProtocol.unpackPacket(packet);
    if (unpacked.expectedLength != null) {
      buf.clear();
      setExpected(unpacked.expectedLength!);
    }
    buf.add(unpacked.body);
    if (expected() > 0 && buf.length >= expected()) {
      final payload = Uint8List.fromList(buf.takeBytes());
      setExpected(0);
      onComplete(payload);
    }
  }

  void _applyStatusPayload(Uint8List payload) {
    final map = GoProProtocol.parseStatusTlvs(payload);
    if (map.isEmpty) return;

    var next = status;
    final encoding = GoProProtocol.readUint(map[GoProProtocol.statusEncoding]);
    if (encoding != null) {
      next = next.copyWith(encoding: encoding != 0);
    }
    final duration =
        GoProProtocol.readUint(map[GoProProtocol.statusEncodingDuration]);
    if (duration != null) {
      next = next.copyWith(encodingDurationSec: duration);
    }
    final batt =
        GoProProtocol.readUint(map[GoProProtocol.statusBatteryPercent]);
    if (batt != null) {
      next = next.copyWith(batteryPercent: batt.clamp(0, 100));
    }
    final wifi =
        GoProProtocol.readUint(map[GoProProtocol.statusWifiApEnabled]);
    if (wifi != null) {
      next = next.copyWith(wifiApEnabled: wifi != 0);
    }

    status = next;
    notifyListeners();
  }

  Future<void> _writeCommand(Uint8List bytes, {bool wait = true}) async {
    final char = _commandReq;
    if (char == null) throw StateError('Bağlı değil');

    Completer<bool>? completer;
    if (wait) {
      completer = Completer<bool>();
      _pendingCommand = completer;
    }

    await char.write(bytes, withoutResponse: false);

    if (completer != null) {
      final ok = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
      if (_pendingCommand == completer) _pendingCommand = null;
      if (!ok) {
        throw StateError('Kamera komutu başarısız veya zaman aşımı');
      }
    }
  }

  Future<void> _writeQuery(Uint8List bytes, {bool wait = false}) async {
    final char = _queryReq;
    if (char == null) return;
    await char.write(bytes, withoutResponse: false);
    if (wait) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> _teardownLink({bool keepState = false}) async {
    for (final sub in _notifySubs) {
      await sub.cancel();
    }
    _notifySubs.clear();
    await _connSub?.cancel();
    _connSub = null;

    final device = _device;
    _device = null;
    _commandReq = null;
    _queryReq = null;
    _wifiSsid = null;
    _wifiPassword = null;

    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
    if (!keepState) {
      // caller sets state
    }
  }

  void _setState(GoProConnectionState s) {
    _state = s;
    notifyListeners();
  }

  static String _friendlyError(Object? e) {
    final text = e?.toString() ?? 'Bilinmeyen hata';
    if (text.contains('133') || text.contains('ANDROID_SPECIFIC_ERROR')) {
      return 'Bluetooth bağlantısı kurulamadı (Android 133). '
          'Kamerayı yeniden başlatıp tekrar dene; ilk seferde '
          'GoPro ekranındaki eşleştirme isteğini onayla.';
    }
    return text;
  }

  static bool _looksLikeGoPro(String name) {
    final n = name.toLowerCase();
    return n.contains('gopro') ||
        n.startsWith('hero') ||
        RegExp(r'^gp[0-9]', caseSensitive: false).hasMatch(n);
  }

  @override
  void dispose() {
    unawaited(disconnect());
    super.dispose();
  }
}
