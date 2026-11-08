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

      // Prefer known/bonded camera — no scan (also wakes a sleeping cam).
      final known = await _resolveKnownDevice();
      if (known != null) {
        try {
          await connect(
            known,
            retries: connectRetries,
            fastRecord: fastRecord,
          );
          return;
        } catch (e) {
          debugPrint('known-device connect failed, scanning: $e');
        }
      }

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

      await stopScan();
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

  /// Bonded / last-used GoPro — connect wakes a sleeping camera.
  Future<GoProDeviceInfo?> _resolveKnownDevice() async {
    GoProDeviceInfo wrap(BluetoothDevice d) {
      final name = d.platformName;
      return GoProDeviceInfo(
        device: d,
        name: name.isNotEmpty ? name : (_lastName ?? 'GoPro'),
        remoteId: d.remoteId.str,
      );
    }

    bool isCandidate(BluetoothDevice d) {
      final id = d.remoteId.str;
      if (_lastRemoteId != null && id == _lastRemoteId) return true;
      return _looksLikeGoPro(d.platformName) || _looksLikeGoPro(d.advName);
    }

    try {
      final bonded = await FlutterBluePlus.bondedDevices;
      GoProDeviceInfo? fallback;
      for (final d in bonded) {
        if (!isCandidate(d)) continue;
        final info = wrap(d);
        if (_lastRemoteId != null && d.remoteId.str == _lastRemoteId) {
          return info;
        }
        fallback ??= info;
      }
      if (fallback != null) return fallback;
    } catch (e) {
      debugPrint('bondedDevices: $e');
    }

    try {
      final sys = await FlutterBluePlus.systemDevices([
        Guid(GoProUuids.controlService),
      ]);
      for (final d in sys) {
        if (!isCandidate(d)) continue;
        final info = wrap(d);
        if (_lastRemoteId != null && d.remoteId.str == _lastRemoteId) {
          return info;
        }
        return info;
      }
    } catch (e) {
      debugPrint('systemDevices: $e');
    }
    return null;
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
  }) async {
    _error = null;
    await stopScan();
    // Android GATT 133 is common if we connect immediately after stopScan.
    await Future<void>.delayed(
      Duration(milliseconds: fastRecord ? 120 : 400),
    );
    _setState(GoProConnectionState.connecting);

    Object? lastError;
    final attempts = fastRecord ? retries.clamp(1, 3) : retries;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        await _connectOnce(
          info,
          attempt: attempt,
          fastRecord: fastRecord,
        );
        connectedDevice = info;
        unawaited(_persistLastDevice(info));
        _error = null;
        _setState(GoProConnectionState.connected);
        return;
      } catch (e) {
        lastError = e;
        debugPrint('GoPro connect attempt $attempt/$attempts failed: $e');
        await _teardownLink(keepState: true);
        await Future<void>.delayed(
          Duration(milliseconds: fastRecord ? 250 * attempt : 500 * attempt),
        );
      }
    }

    _error = _friendlyError(lastError);
    _setState(GoProConnectionState.error);
    throw StateError(_error!);
  }

  Future<void> _connectOnce(
    GoProDeviceInfo info, {
    required int attempt,
    bool fastRecord = false,
  }) async {
    final device = info.device;
    _device = device;

    // Always force a clean disconnect before connect (Android 133 mitigation).
    try {
      await device.disconnect();
    } catch (_) {}
    await Future<void>.delayed(
      Duration(milliseconds: fastRecord ? 80 : 250),
    );

    if (!fastRecord && attempt >= 3) {
      try {
        await device.clearGattCache();
      } catch (_) {}
    }

    // Connecting while asleep wakes the GoPro over BLE.
    await device.connect(
      timeout: Duration(seconds: fastRecord ? 15 : 25),
      autoConnect: false,
      mtu: null,
    );

    await device.connectionState
        .firstWhere((s) => s == BluetoothConnectionState.connected)
        .timeout(Duration(seconds: fastRecord ? 12 : 20));

    // Skip createBond when already paired — biggest delay after wake.
    try {
      final bond = await device.bondState.first.timeout(
        const Duration(milliseconds: 800),
        onTimeout: () => BluetoothBondState.none,
      );
      if (bond != BluetoothBondState.bonded) {
        await device.createBond(timeout: fastRecord ? 20 : 45);
      }
    } catch (e) {
      debugPrint('Bond/pair note: $e');
    }

    await _connSub?.cancel();
    _connSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected &&
          (_state == GoProConnectionState.connected || _sessionRecording)) {
        _error = 'Bağlantı koptu';
        connectedDevice = null;
        if (!_sessionRecording) {
          _setState(GoProConnectionState.disconnected);
        }
      }
    });

    if (!fastRecord) {
      try {
        await device.requestMtu(512);
      } catch (_) {}
    }

    await device.discoverServices();
    await _bindCharacteristics(device);
    // Command (+ query) notifies only — enough to start shutter immediately.
    await _enableNotifications(device, minimal: fastRecord);

    await _writeCommand(GoProProtocol.setThirdPartyClientInfo(), wait: false);

    if (fastRecord) {
      // Status registration after shutter — don't block wake→record.
      unawaited(_finishInitAfterRecordReady());
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _writeQuery(GoProProtocol.registerAllSettings(), wait: false);
    await _writeQuery(GoProProtocol.registerAllStatuses(), wait: false);
  }

  Future<void> _finishInitAfterRecordReady() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await _writeQuery(GoProProtocol.registerAllSettings(), wait: false);
      await _writeQuery(GoProProtocol.registerAllStatuses(), wait: false);
    } catch (e) {
      debugPrint('deferred init: $e');
    }
  }

  Future<void> disconnect() async {
    await stopScan();
    await _teardownLink();
    connectedDevice = null;
    status = const GoProCameraStatus();
    _setState(GoProConnectionState.disconnected);
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

  /// Single control: start = wake/connect fast + shutter;
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

    // Wake (via BLE connect) + shutter ASAP — skip full status init.
    if (!isConnected) {
      await autoConnect(
        scanTimeout: const Duration(seconds: 12),
        connectRetries: 3,
        fastRecord: true,
      );
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
