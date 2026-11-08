import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Last successful camera — used to skip scan and wake via direct connect.
  String? _lastRemoteId;
  String? _lastName;
  static const _prefsIdKey = 'gopro_last_remote_id';
  static const _prefsNameKey = 'gopro_last_name';
  bool _prefsLoaded = false;

  bool get isConnected =>
      _state == GoProConnectionState.connected && _device != null;

  Future<void> ensurePrefsLoaded() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      _lastRemoteId = p.getString(_prefsIdKey);
      _lastName = p.getString(_prefsNameKey);
    } catch (_) {}
  }

  Future<void> _persistLastDevice(GoProDeviceInfo info) async {
    _lastRemoteId = info.remoteId;
    _lastName = info.name;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefsIdKey, info.remoteId);
      await p.setString(_prefsNameKey, info.name);
    } catch (_) {}
  }

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
    Duration scanTimeout = const Duration(seconds: 8),
    int connectRetries = 3,
    bool fastRecord = true,
  }) async {
    if (isConnected || _autoConnectInFlight) return;
    _autoConnectInFlight = true;
    _error = null;
    notifyListeners();

    try {
      await ensurePrefsLoaded();
      await ensureAdapterOn();

      // Always scan for a fresh advertisement before connect (Android).
      final target = await _scanForFreshGoPro(timeout: scanTimeout);
      await connect(
        target,
        retries: connectRetries,
        fastRecord: fastRecord,
      );
    } finally {
      _autoConnectInFlight = false;
      notifyListeners();
    }
  }

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 8),
    bool autoConnectFirst = false,
  }) async {
    _error = null;
    discovered.clear();
    _firstDeviceCompleter = Completer<GoProDeviceInfo>();
    _setState(GoProConnectionState.scanning);

    await ensureAdapterOn();
    await _scanSub?.cancel();

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    final controlGuid = Guid(GoProUuids.controlService);

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      var foundNew = false;
      for (final r in results) {
        final platformName = r.device.platformName;
        final advName = r.advertisementData.advName;
        final name = platformName.isNotEmpty
            ? platformName
            : (advName.isNotEmpty ? advName : '');
        final hasGoProService = r.advertisementData.serviceUuids.any(
          (u) =>
              u == controlGuid ||
              u.str128.toLowerCase() == GoProUuids.controlService,
        );
        final nameMatch = name.isNotEmpty && _looksLikeGoPro(name);
        final knownId =
            _lastRemoteId != null && r.device.remoteId.str == _lastRemoteId;
        if (!nameMatch && !hasGoProService && !knownId) continue;

        final id = r.device.remoteId.str;
        final displayName = name.isNotEmpty
            ? name
            : (_lastName ?? (knownId ? 'GoPro' : 'GoPro'));
        final existing = discovered.indexWhere((d) => d.remoteId == id);
        final info = GoProDeviceInfo(
          device: r.device,
          name: displayName,
          remoteId: id,
          rssi: r.rssi,
        );
        if (existing >= 0) {
          discovered[existing] = info;
        } else {
          discovered.add(info);
          foundNew = true;
          final pending = _firstDeviceCompleter;
          if (pending != null && !pending.isCompleted) {
            pending.complete(info);
          }
        }
      }
      discovered.sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
      notifyListeners();
      // Stop ASAP so we don't sit on "Taranıyor…" after the camera is seen.
      if (autoConnectFirst && foundNew) {
        unawaited(FlutterBluePlus.stopScan());
      }
    });

    // Don't filter withServices here — some firmware omits FEA6 from the
    // advertising packet and only puts it in the scan response / GATT.
    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: true,
      androidScanMode: AndroidScanMode.lowLatency,
      continuousUpdates: true,
    );

    if (autoConnectFirst) {
      try {
        await _firstDeviceCompleter!.future.timeout(timeout);
      } on TimeoutException {
        // caller handles empty list
      }
      await FlutterBluePlus.stopScan();
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
    bool fastRecord = false,
    bool shutterOnConnect = false,
  }) async {
    _error = null;
    await stopScan();
    if (!fastRecord) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    _setState(GoProConnectionState.connecting);

    Object? lastError;
    final attempts = fastRecord ? retries.clamp(1, 3) : retries;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        await _connectOnce(
          info,
          attempt: attempt,
          fastRecord: fastRecord,
          shutterOnConnect: shutterOnConnect,
        );
        connectedDevice = info;
        unawaited(_persistLastDevice(info));
        _error = null;
        _setState(GoProConnectionState.connected);
        return;
      } catch (e) {
        lastError = e;
        debugPrint('GoPro connect attempt $attempt/$attempts failed: $e');
        // Never leave the UI stuck on "KAYIT" after a failed connect.
        _sessionRecording = false;
        status = const GoProCameraStatus();
        await _teardownLink(keepState: true);
        await Future<void>.delayed(
          Duration(milliseconds: fastRecord ? 350 * attempt : 500 * attempt),
        );
      }
    }

    _sessionRecording = false;
    status = const GoProCameraStatus();
    connectedDevice = null;
    _error = _friendlyError(lastError);
    _setState(GoProConnectionState.error);
    notifyListeners();
    throw StateError(_error!);
  }

  Future<void> _connectOnce(
    GoProDeviceInfo info, {
    required int attempt,
    bool fastRecord = false,
    bool shutterOnConnect = false,
  }) async {
    final device = info.device;
    _device = device;

    // Only disconnect if already linked — avoid extra wake delay.
    if (device.isConnected) {
      try {
        await device.disconnect();
      } catch (_) {}
      await Future<void>.delayed(
        Duration(milliseconds: fastRecord ? 80 : 250),
      );
    }

    // GATT 133 mitigation: clear cache on retry.
    if (attempt >= 2) {
      try {
        await device.clearGattCache();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    // Brief settle after scan stop before GATT connect (helps 133).
    if (fastRecord && attempt == 1) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    await device.connect(
      timeout: Duration(seconds: fastRecord ? 8 : 20),
      autoConnect: false,
      mtu: null,
    );

    await device.connectionState
        .firstWhere((s) => s == BluetoothConnectionState.connected)
        .timeout(Duration(seconds: fastRecord ? 8 : 15));

    // Never block the record path on bonding.
    if (!fastRecord) {
      try {
        final bond = await device.bondState.first.timeout(
          const Duration(milliseconds: 800),
          onTimeout: () => BluetoothBondState.none,
        );
        if (bond != BluetoothBondState.bonded) {
          await device.createBond(timeout: 45);
        }
      } catch (e) {
        debugPrint('Bond/pair note: $e');
      }
    }

    await _connSub?.cancel();
    _connSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected &&
          (_state == GoProConnectionState.connected || _sessionRecording)) {
        _error = 'Bağlantı koptu';
        connectedDevice = null;
        // Drop phantom "KAYIT" UI if the link dies mid-session.
        _sessionRecording = false;
        status = const GoProCameraStatus();
        _setState(GoProConnectionState.disconnected);
      }
    });

    if (!fastRecord) {
      try {
        await device.requestMtu(512);
      } catch (_) {}
    }

    await device.discoverServices(timeout: fastRecord ? 8 : 15);
    await _bindCharacteristics(device);

    // RECORD FAST PATH: prime CCCD + third-party, then shutter (no 15s waits).
    if (shutterOnConnect) {
      await _primeCommandChannel(device);
      await _burstStartShutter();
      unawaited(_finishInitAfterRecordReady(device));
      return;
    }

    await _enableNotifications(device, minimal: fastRecord);
    await _writeCommand(GoProProtocol.setThirdPartyClientInfo(), wait: false);

    if (fastRecord) {
      unawaited(_finishInitAfterRecordReady(device));
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _writeQuery(GoProProtocol.registerAllSettings(), wait: false);
    await _writeQuery(GoProProtocol.registerAllStatuses(), wait: false);
  }

  /// Enable command/query notifies and announce third-party client.
  /// Failures are ignored — shutter still proceeds with a short settle.
  Future<void> _primeCommandChannel(BluetoothDevice device) async {
    try {
      await _enableNotifications(device, minimal: true);
    } catch (e) {
      debugPrint('prime notify: $e');
    }
    try {
      await _bleWrite(
        _commandReq,
        GoProProtocol.setThirdPartyClientInfo(),
        withoutResponse: true,
        timeoutSec: 2,
      );
    } catch (e) {
      debugPrint('prime third-party: $e');
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  /// Fire shutter with short Write-Without-Response timeouts only.
  /// Never falls back to Write-With-Response (that was the 15s hang).
  Future<void> _burstStartShutter() async {
    final char = _commandReq;
    if (char == null) throw StateError('Komut karakteristiği yok');

    Object? lastErr;
    for (var i = 0; i < 4; i++) {
      try {
        await _bleWrite(
          char,
          GoProProtocol.setShutter(on: true),
          withoutResponse: true,
          timeoutSec: 2,
        );
        lastErr = null;
        break;
      } catch (e) {
        lastErr = e;
        debugPrint('shutter burst $i: $e');
        await Future<void>.delayed(Duration(milliseconds: 120 + i * 60));
      }
    }
    if (lastErr != null) {
      throw StateError(
        'Kayıt komutu gönderilemedi. Kamerayı uyandırıp tekrar dene.',
      );
    }

    _sessionRecording = true;
    status = status.copyWith(encoding: true);
    notifyListeners();
  }

  Future<void> _bleWrite(
    BluetoothCharacteristic? char,
    Uint8List bytes, {
    required bool withoutResponse,
    int timeoutSec = 3,
  }) async {
    if (char == null) throw StateError('Bağlı değil');
    await char.write(
      bytes,
      withoutResponse: withoutResponse,
      timeout: timeoutSec,
    );
  }

  void _resetSessionLocal({String? error}) {
    _sessionRecording = false;
    status = const GoProCameraStatus();
    connectedDevice = null;
    if (error != null) _error = error;
    _setState(GoProConnectionState.disconnected);
  }

  Future<void> _finishInitAfterRecordReady(BluetoothDevice device) async {
    try {
      await _enableNotifications(device, minimal: true);
      await _writeCommand(GoProProtocol.setThirdPartyClientInfo(), wait: false);
      await _writeQuery(GoProProtocol.registerAllSettings(), wait: false);
      await _writeQuery(GoProProtocol.registerAllStatuses(), wait: false);
    } catch (e) {
      debugPrint('deferred init: $e');
    }
  }

  Future<void> disconnect() async {
    await stopScan();
    await _teardownLink();
    _resetSessionLocal();
  }

  Future<void> startRecording() async {
    // Don't block forever on notify — wake path may be busy settling.
    try {
      await _writeCommand(
        GoProProtocol.setShutter(on: true),
        wait: true,
      ).timeout(const Duration(seconds: 3));
    } catch (e) {
      // Write often still landed; keep going so the UI isn't stuck on connect.
      debugPrint('shutter start: $e');
    }
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
    try {
      await _bleWrite(
        _commandReq,
        bytes,
        withoutResponse: true,
        timeoutSec: 2,
      );
    } catch (e) {
      debugPrint('fire-and-forget write: $e');
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

  /// Single control: start = wake + shutter; stop = stop + sleep.
  /// If link is already dead, STOP just clears local phantom "KAYIT" state.
  Future<void> toggleRecording() async {
    if (isSessionRecording) {
      // Phantom session after GATT 133 / drop — don't require a live link.
      if (!isConnected || _commandReq == null) {
        await _teardownLink();
        _resetSessionLocal();
        return;
      }

      try {
        await stopRecording();
      } catch (e) {
        debugPrint('stopRecording: $e');
        _sessionRecording = false;
      }

      await _waitUntilNotEncoding();

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
      _resetSessionLocal();
      return;
    }

    try {
      await wakeAndRecord();
    } catch (e) {
      _resetSessionLocal(error: _friendlyError(e));
      rethrow;
    }
  }

  /// Press-path: short scan for a *fresh* advertisement → connect → shutter.
  ///
  /// Android is very slow (10–20s+) if you connect to a bonded device without
  /// a recent scan result. Always scan first; never hang on bonded-only connect.
  Future<void> wakeAndRecord() async {
    _error = null;
    await ensurePrefsLoaded();
    await ensureAdapterOn();

    if (isConnected && _commandReq != null) {
      await _burstStartShutter();
      return;
    }

    // Abort any leftover scan / connect attempt.
    try {
      await stopScan();
    } catch (_) {}

    final target = await _scanForFreshGoPro(
      timeout: const Duration(seconds: 4),
    );

    await connect(
      target,
      retries: 2,
      fastRecord: true,
      shutterOnConnect: true,
    );
  }

  /// Low-latency scan; prefers last camera id, otherwise first GoPro seen.
  Future<GoProDeviceInfo> _scanForFreshGoPro({
    required Duration timeout,
  }) async {
    discovered.clear();
    _setState(GoProConnectionState.scanning);

    final done = Completer<GoProDeviceInfo>();
    GoProDeviceInfo? fallback;
    await _scanSub?.cancel();

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    final controlGuid = Guid(GoProUuids.controlService);

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final platformName = r.device.platformName;
        final advName = r.advertisementData.advName;
        final name = platformName.isNotEmpty
            ? platformName
            : (advName.isNotEmpty ? advName : '');
        final hasGoProService = r.advertisementData.serviceUuids.any(
          (u) =>
              u == controlGuid ||
              u.str128.toLowerCase() == GoProUuids.controlService,
        );
        final nameMatch = name.isNotEmpty && _looksLikeGoPro(name);
        final knownId =
            _lastRemoteId != null && r.device.remoteId.str == _lastRemoteId;
        if (!nameMatch && !hasGoProService && !knownId) continue;

        final info = GoProDeviceInfo(
          device: r.device,
          name: name.isNotEmpty ? name : (_lastName ?? 'GoPro'),
          remoteId: r.device.remoteId.str,
          rssi: r.rssi,
        );
        final existing =
            discovered.indexWhere((d) => d.remoteId == info.remoteId);
        if (existing >= 0) {
          discovered[existing] = info;
        } else {
          discovered.add(info);
        }
        discovered.sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
        notifyListeners();

        // Prefer remembered id, otherwise first GoPro wins — never wait around.
        if (knownId || !done.isCompleted) {
          if (knownId || fallback == null) {
            fallback = info;
          }
          if (knownId) {
            if (!done.isCompleted) done.complete(info);
            unawaited(FlutterBluePlus.stopScan());
            return;
          }
          if (!done.isCompleted) {
            done.complete(info);
            unawaited(FlutterBluePlus.stopScan());
          }
        }
      }
    });

    Future<void> beginScan({List<String> remoteIds = const []}) {
      return FlutterBluePlus.startScan(
        withRemoteIds: remoteIds,
        timeout: timeout,
        androidUsesFineLocation: true,
        androidScanMode: AndroidScanMode.lowLatency,
        continuousUpdates: true,
      );
    }

    // Narrow scan to last camera when known — much faster on Android.
    if (_lastRemoteId != null) {
      await beginScan(remoteIds: [_lastRemoteId!]);
      try {
        return await done.future.timeout(timeout);
      } on TimeoutException {
        if (discovered.isNotEmpty) return discovered.first;
        // Fall through to wide scan.
        await FlutterBluePlus.stopScan();
      }
    }

    await beginScan();
    try {
      return await done.future.timeout(timeout);
    } on TimeoutException {
      if (discovered.isNotEmpty) return discovered.first;
      if (fallback != null) return fallback!;
      throw StateError(
        'GoPro bulunamadı (tarama ${timeout.inSeconds}sn). '
        'Kamerayı aç/yakına al, Bluetooth açık olsun.',
      );
    } finally {
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      _scanSub = null;
    }
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

  Future<void> _enableNotifications(
    BluetoothDevice device, {
    bool minimal = false,
  }) async {
    for (final sub in _notifySubs) {
      await sub.cancel();
    }
    _notifySubs.clear();

    for (final service in device.servicesList) {
      for (final c in service.characteristics) {
        if (!c.properties.notify && !c.properties.indicate) continue;
        final u = c.uuid.str128.toLowerCase();
        if (minimal &&
            u != GoProUuids.commandRsp &&
            u != GoProUuids.queryRsp) {
          continue;
        }
        try {
          await c.setNotifyValue(true, timeout: 3);
        } catch (e) {
          debugPrint('setNotifyValue $u: $e');
          continue;
        }
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
    Completer<bool>? completer;
    if (wait) {
      completer = Completer<bool>();
      _pendingCommand = completer;
    }

    // Prefer withoutResponse so we never sit on FBP's 15s ATT timeout.
    await _bleWrite(
      _commandReq,
      bytes,
      withoutResponse: true,
      timeoutSec: wait ? 3 : 2,
    );

    if (completer != null) {
      final ok = await completer.future.timeout(
        const Duration(seconds: 3),
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
    try {
      await _bleWrite(char, bytes, withoutResponse: true, timeoutSec: 2);
    } catch (e) {
      debugPrint('query write: $e');
    }
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
    if (text.contains('writeCharacteristic') ||
        text.contains('Timed out') ||
        text.contains('zaman aşımı') ||
        text.contains('gönderilemedi')) {
      return 'Kamera komutu zaman aşımına uğradı. '
          'Kamerayı açıp tekrar KAYIT’a bas.';
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
