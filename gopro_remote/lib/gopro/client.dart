import 'dart:async';
import 'dart:convert';
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
  Completer<GoProDeviceInfo>? _activeScanCompleter;

  /// Local session flag — encoding status notifications can lag or miss,
  /// so the single record button must not rely only on [status.encoding].
  bool _sessionRecording = false;
  bool get isSessionRecording => _sessionRecording || status.encoding;

  /// Saved cameras (multi-device). Preferred target for KAYIT / wake.
  final List<SavedGoProDevice> _savedDevices = [];
  String? _selectedRemoteId;
  static const _prefsSavedKey = 'gopro_saved_devices_v1';
  static const _prefsSelectedKey = 'gopro_selected_remote_id';
  // Legacy single-camera keys — migrated once into the list above.
  static const _prefsIdKey = 'gopro_last_remote_id';
  static const _prefsNameKey = 'gopro_last_name';
  bool _prefsLoaded = false;

  /// After sleep the camera needs a short cool-down before the next GATT
  /// connect, otherwise Android frequently returns status 133.
  DateTime? _lastSleepAt;

  /// User-facing long operations (KAYIT / bağlan) can be aborted via [cancelOperation].
  bool _cancelRequested = false;
  bool get isCancelRequested => _cancelRequested;

  bool get isConnected =>
      _state == GoProConnectionState.connected && _device != null;

  void beginOperation() {
    _cancelRequested = false;
  }

  /// Abort scan/connect/wake in progress and drop any half-open GATT link.
  Future<void> cancelOperation() async {
    _cancelRequested = true;
    _error = null;
    notifyListeners();
    try {
      await stopScan();
    } catch (_) {}
    for (final pending in [_firstDeviceCompleter, _activeScanCompleter]) {
      if (pending != null && !pending.isCompleted) {
        pending.completeError(const GoProCancelledException());
      }
    }
    final cmd = _pendingCommand;
    if (cmd != null && !cmd.isCompleted) {
      cmd.complete(false);
    }
    try {
      await _device?.disconnect();
    } catch (_) {}
    try {
      for (final d in FlutterBluePlus.connectedDevices) {
        try {
          await d.disconnect();
        } catch (_) {}
      }
    } catch (_) {}
    await _teardownLink(keepState: true);
    _sessionRecording = false;
    status = const GoProCameraStatus();
    connectedDevice = null;
    _setState(GoProConnectionState.disconnected);
  }

  void _ensureNotCancelled() {
    if (_cancelRequested) {
      throw const GoProCancelledException();
    }
  }

  Future<void> _delayCancellable(Duration duration) async {
    if (duration <= Duration.zero) {
      _ensureNotCancelled();
      return;
    }
    const slice = Duration(milliseconds: 100);
    var left = duration;
    while (left > Duration.zero) {
      _ensureNotCancelled();
      final step = left < slice ? left : slice;
      await Future<void>.delayed(step);
      left -= step;
    }
    _ensureNotCancelled();
  }

  List<SavedGoProDevice> get savedDevices =>
      List<SavedGoProDevice>.unmodifiable(_savedDevices);

  SavedGoProDevice? get selectedSaved {
    final id = _selectedRemoteId;
    if (id == null) return null;
    for (final d in _savedDevices) {
      if (d.remoteId == id) return d;
    }
    return _savedDevices.isEmpty ? null : _savedDevices.first;
  }

  String? get preferredRemoteId => selectedSaved?.remoteId;

  String? get preferredName => selectedSaved?.name;

  Future<void> ensurePrefsLoaded() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsSavedKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(SavedGoProDevice.fromJson)
            .where((d) => d.remoteId.isNotEmpty)
            .toList();
        _savedDevices
          ..clear()
          ..addAll(list);
      } else {
        // Migrate v0 single last-camera prefs.
        final legacyId = p.getString(_prefsIdKey);
        final legacyName = p.getString(_prefsNameKey);
        if (legacyId != null && legacyId.isNotEmpty) {
          _savedDevices.add(
            SavedGoProDevice(
              remoteId: legacyId,
              name: (legacyName == null || legacyName.isEmpty)
                  ? 'GoPro'
                  : legacyName,
              addedAtMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
          await _persistSavedDevices(p);
        }
      }
      _selectedRemoteId = p.getString(_prefsSelectedKey);
      if (_selectedRemoteId == null && _savedDevices.isNotEmpty) {
        _selectedRemoteId = _savedDevices.first.remoteId;
        await p.setString(_prefsSelectedKey, _selectedRemoteId!);
      }
      if (_selectedRemoteId != null &&
          _savedDevices.every((d) => d.remoteId != _selectedRemoteId)) {
        _selectedRemoteId =
            _savedDevices.isEmpty ? null : _savedDevices.first.remoteId;
        if (_selectedRemoteId == null) {
          await p.remove(_prefsSelectedKey);
        } else {
          await p.setString(_prefsSelectedKey, _selectedRemoteId!);
        }
      }
    } catch (e) {
      debugPrint('prefs load: $e');
    }
    notifyListeners();
  }

  Future<void> _persistSavedDevices([SharedPreferences? prefs]) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final encoded =
          jsonEncode(_savedDevices.map((d) => d.toJson()).toList());
      await p.setString(_prefsSavedKey, encoded);
      if (_selectedRemoteId == null) {
        await p.remove(_prefsSelectedKey);
      } else {
        await p.setString(_prefsSelectedKey, _selectedRemoteId!);
      }
      // Keep legacy keys in sync for older code paths / debugging.
      final sel = selectedSaved;
      if (sel == null) {
        await p.remove(_prefsIdKey);
        await p.remove(_prefsNameKey);
      } else {
        await p.setString(_prefsIdKey, sel.remoteId);
        await p.setString(_prefsNameKey, sel.name);
      }
    } catch (e) {
      debugPrint('prefs save: $e');
    }
  }

  Future<void> selectSavedDevice(String remoteId) async {
    await ensurePrefsLoaded();
    if (_savedDevices.every((d) => d.remoteId != remoteId)) return;
    _selectedRemoteId = remoteId;
    await _persistSavedDevices();
    notifyListeners();
  }

  /// Persist a camera from scan / successful connect and make it active.
  Future<void> saveDevice({
    required String remoteId,
    required String name,
    bool select = true,
  }) async {
    await ensurePrefsLoaded();
    final existing = _savedDevices.indexWhere((d) => d.remoteId == remoteId);
    if (existing >= 0) {
      _savedDevices[existing] =
          _savedDevices[existing].copyWith(name: name.isEmpty ? null : name);
    } else {
      _savedDevices.add(
        SavedGoProDevice(
          remoteId: remoteId,
          name: name.isEmpty ? 'GoPro' : name,
          addedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    if (select) _selectedRemoteId = remoteId;
    await _persistSavedDevices();
    notifyListeners();
  }

  Future<void> forgetSavedDevice(String remoteId) async {
    await ensurePrefsLoaded();
    _savedDevices.removeWhere((d) => d.remoteId == remoteId);
    if (_selectedRemoteId == remoteId) {
      _selectedRemoteId =
          _savedDevices.isEmpty ? null : _savedDevices.first.remoteId;
    }
    if (connectedDevice?.remoteId == remoteId) {
      try {
        await disconnect();
      } catch (_) {}
    }
    try {
      final device = BluetoothDevice.fromId(remoteId);
      await device.removeBond(timeout: 8);
    } catch (e) {
      debugPrint('forget removeBond: $e');
    }
    await _persistSavedDevices();
    notifyListeners();
  }

  Future<void> _persistLastDevice(GoProDeviceInfo info) async {
    await saveDevice(remoteId: info.remoteId, name: info.name, select: true);
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

  /// Wake + BLE connect only (no shutter). Used by “Sadece bağlan”.
  Future<void> autoConnect({
    Duration scanTimeout = const Duration(seconds: 5),
    int connectRetries = 2,
    bool fastRecord = true,
  }) async {
    if (isConnected || _autoConnectInFlight) return;
    await wakeAndConnect(
      scanTimeout: scanTimeout,
      connectRetries: connectRetries,
      fastRecord: fastRecord,
    );
  }

  /// Bottom-button toggle: disconnected → wake/connect; connected → sleep/close.
  Future<void> toggleConnectSleep() async {
    if (isConnected || isSessionRecording) {
      await sleepAndDisconnect();
      return;
    }
    await wakeAndConnect();
  }

  /// Put camera to sleep (if linked) and clear local BLE session — no recording.
  Future<void> sleepAndDisconnect() async {
    _error = null;
    _ensureNotCancelled();

    if (isSessionRecording && _commandReq != null) {
      try {
        await stopRecording();
      } catch (e) {
        debugPrint('stop before sleep/disconnect: $e');
        _sessionRecording = false;
      }
      await _waitUntilNotEncoding();
    }

    final sleeping = _device;
    if (sleeping != null && _commandReq != null) {
      try {
        await sleepCamera();
      } catch (e) {
        debugPrint('sleepAndDisconnect sleep: $e');
      }
      try {
        await sleeping.connectionState
            .firstWhere((s) => s == BluetoothConnectionState.disconnected)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        if (_cancelRequested) throw const GoProCancelledException();
        try {
          await sleeping.disconnect();
        } catch (_) {}
      }
    }

    await _delayCancellable(const Duration(milliseconds: 300));
    await _teardownLink();
    _lastSleepAt = DateTime.now();
    _resetSessionLocal();
  }

  /// Fresh scan → connect, without starting a recording.
  Future<void> wakeAndConnect({
    Duration scanTimeout = const Duration(seconds: 3),
    int connectRetries = 2,
    bool fastRecord = true,
  }) async {
    if (isConnected) return;
    if (_autoConnectInFlight) return;
    _autoConnectInFlight = true;
    _error = null;
    notifyListeners();

    try {
      await ensurePrefsLoaded();
      await ensureAdapterOn();
      _ensureNotCancelled();

      try {
        await stopScan();
      } catch (_) {}
      await _awaitPostSleepCooldown();

      Object? lastError;
      const attempts = 2;
      for (var attempt = 1; attempt <= attempts; attempt++) {
        _ensureNotCancelled();
        try {
          final target = await _scanForFreshGoPro(
            timeout: attempt == 1
                ? scanTimeout
                : Duration(seconds: scanTimeout.inSeconds + 2),
          );
          await connect(
            target,
            retries: connectRetries,
            fastRecord: fastRecord,
            shutterOnConnect: false,
          );
          return;
        } catch (e) {
          if (e is GoProCancelledException || _cancelRequested) rethrow;
          lastError = e;
          debugPrint('wakeAndConnect attempt $attempt/$attempts: $e');
          await _teardownLink(keepState: true);
          await _delayCancellable(Duration(milliseconds: 350 * attempt));
        }
      }

      _error = _friendlyError(lastError);
      _setState(GoProConnectionState.error);
      notifyListeners();
      throw StateError(_error!);
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
        final id = r.device.remoteId.str;
        final knownId = _isKnownRemoteId(id);
        if (!nameMatch && !hasGoProService && !knownId) continue;

        final displayName = name.isNotEmpty
            ? name
            : (_savedNameFor(id) ?? 'GoPro');
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
    await _waitScanFullyStopped(fastRecord: fastRecord);
    await _awaitPostSleepCooldown();
    _setState(GoProConnectionState.connecting);

    Object? lastError;
    // Short direct GATT retries. Do NOT cycle the phone Bluetooth adapter —
    // turnOff is broken/deprecated on modern Android and was making "used to
    // connect, now doesn't" worse after the first success.
    final attempts = fastRecord ? retries.clamp(1, 3) : retries;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      _ensureNotCancelled();
      if (attempt > 1) {
        await _disconnectAllBleClients();
      }
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
        _lastSleepAt = null;
        _setState(GoProConnectionState.connected);
        return;
      } catch (e) {
        if (e is GoProCancelledException || _cancelRequested) rethrow;
        lastError = e;
        debugPrint('GoPro connect attempt $attempt/$attempts failed: $e');
        _sessionRecording = false;
        status = const GoProCameraStatus();
        await _teardownLink(keepState: true);
        try {
          await BluetoothDevice.fromId(info.remoteId).disconnect();
        } catch (_) {}
        final is133 = e.toString().contains('133') ||
            e.toString().contains('ANDROID_SPECIFIC_ERROR') ||
            e.toString().contains('GATT_ERROR');
        await _delayCancellable(
          Duration(
            milliseconds: is133 ? (500 + attempt * 300) : (400 * attempt),
          ),
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

  Future<void> _waitScanFullyStopped({bool fastRecord = false}) async {
    _ensureNotCancelled();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
    final deadline = DateTime.now().add(
      Duration(milliseconds: fastRecord ? 600 : 2000),
    );
    while (FlutterBluePlus.isScanningNow &&
        DateTime.now().isBefore(deadline)) {
      _ensureNotCancelled();
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    // Brief settle only — long waits here added seconds before every KAYIT.
    await _delayCancellable(
      Duration(milliseconds: fastRecord ? 250 : 600),
    );
  }

  Future<void> _disconnectAllBleClients() async {
    try {
      for (final d in FlutterBluePlus.connectedDevices) {
        try {
          await d.disconnect();
        } catch (_) {}
      }
    } catch (_) {}
    await _delayCancellable(const Duration(milliseconds: 150));
  }

  Future<void> _awaitPostSleepCooldown() async {
    final slept = _lastSleepAt;
    if (slept == null) return;
    // Keep short: wake advertising is usually ready well under a second.
    const coolDown = Duration(milliseconds: 500);
    final elapsed = DateTime.now().difference(slept);
    if (elapsed < coolDown) {
      await _delayCancellable(coolDown - elapsed);
    }
  }

  Future<void> _connectOnce(
    GoProDeviceInfo info, {
    required int attempt,
    bool fastRecord = false,
    bool shutterOnConnect = false,
  }) async {
    // Fresh device handle — avoids stale GATT objects from a prior scan.
    final device = BluetoothDevice.fromId(info.remoteId);
    _device = device;

    if (device.isConnected) {
      try {
        await device.disconnect();
      } catch (_) {}
      await Future<void>.delayed(
        Duration(milliseconds: fastRecord ? 120 : 350),
      );
    }

    await device.connect(
      timeout: Duration(seconds: fastRecord ? 7 : 15),
      autoConnect: false,
      mtu: null,
    );

    await device.connectionState
        .firstWhere((s) => s == BluetoothConnectionState.connected)
        .timeout(Duration(seconds: fastRecord ? 7 : 15));

    // Minimal settle after wake — shutter retries cover remaining boot time.
    await _delayCancellable(
      Duration(
        milliseconds: shutterOnConnect
            ? (120 + (attempt - 1) * 80)
            : (_lastSleepAt != null ? 250 : 150),
      ),
    );
    _ensureNotCancelled();

    await _connSub?.cancel();
    _connSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected &&
          (_state == GoProConnectionState.connected || _sessionRecording)) {
        _error = 'Bağlantı koptu';
        connectedDevice = null;
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

    await device.discoverServices(timeout: fastRecord ? 6 : 15);
    await _bindCharacteristics(device);

    await _ensureBonded(
      device,
      promptSeconds: shutterOnConnect || fastRecord ? 10 : 45,
    );

    if (shutterOnConnect) {
      // FAST PATH: shutter as soon as CQ_COMMAND exists.
      // Skipping notify + "command ready" probes was ~10–15s of the old delay.
      try {
        await _bleWrite(
          _commandReq,
          GoProProtocol.setThirdPartyClientInfo(),
          preferWithoutResponse: true,
          timeoutSec: 1,
        );
      } catch (e) {
        debugPrint('fast third-party: $e');
      }
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

  /// Bond only when needed. Already-paired cameras skip the slow pair path.
  Future<void> _ensureBonded(
    BluetoothDevice device, {
    int promptSeconds = 20,
  }) async {
    try {
      var bond = await device.bondState.first.timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => BluetoothBondState.none,
      );
      if (bond == BluetoothBondState.bonded) return;

      // Unbonded: read WAP_PASSWORD to trigger SMP (Open GoPro / ClipRide).
      final wifiPw = _wifiPassword;
      if (wifiPw != null) {
        try {
          await wifiPw.read(timeout: 4);
        } catch (e) {
          debugPrint('wap password read (pair trigger): $e');
        }
        try {
          bond = await device.bondState
              .firstWhere((b) => b == BluetoothBondState.bonded)
              .timeout(Duration(seconds: promptSeconds.clamp(3, 12)));
          if (bond == BluetoothBondState.bonded) return;
        } on TimeoutException {
          // Fall through to createBond.
        }
      }

      bond = await device.bondState.first.timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => BluetoothBondState.none,
      );
      if (bond == BluetoothBondState.bonded) return;

      await device.createBond(timeout: promptSeconds.clamp(5, 20));
    } catch (e) {
      debugPrint('bond/pair: $e');
    }
  }

  /// Fire shutter quickly; camera wake is covered by short retries, not a
  /// multi-second "ready" probe beforehand.
  Future<void> _burstStartShutter() async {
    final char = _commandReq;
    if (char == null) throw StateError('Komut karakteristiği yok');

    Object? lastErr;
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    var i = 0;
    while (DateTime.now().isBefore(deadline)) {
      _ensureNotCancelled();
      try {
        await _bleWrite(
          char,
          GoProProtocol.setShutter(on: true),
          preferWithoutResponse: true,
          timeoutSec: 1,
        );
        lastErr = null;
        break;
      } catch (e) {
        if (e is GoProCancelledException) rethrow;
        lastErr = e;
        debugPrint('shutter burst $i: $e');
        i++;
        await _delayCancellable(Duration(milliseconds: 80 + i * 60));
      }
    }
    if (lastErr != null) {
      throw StateError(
        'Kayıt komutu gönderilemedi. Kamerayı aç / eşleştirmeyi onayla, '
        'sonra tekrar dene.',
      );
    }

    _sessionRecording = true;
    status = status.copyWith(encoding: true);
    notifyListeners();
  }

  Future<void> _bleWrite(
    BluetoothCharacteristic? char,
    Uint8List bytes, {
    required bool preferWithoutResponse,
    int timeoutSec = 3,
  }) async {
    if (char == null) throw StateError('Bağlı değil');
    final props = char.properties;
    var withoutResponse = preferWithoutResponse;
    if (withoutResponse && !props.writeWithoutResponse) {
      // Characteristic only supports Write-With-Response.
      withoutResponse = false;
    }
    if (!withoutResponse && !props.write && props.writeWithoutResponse) {
      withoutResponse = true;
    }
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
        preferWithoutResponse: true,
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
      _ensureNotCancelled();
      await _delayCancellable(const Duration(milliseconds: 150));
    }
    // Brief settle even if status never flipped (some FW skip the notify).
    await _delayCancellable(const Duration(milliseconds: 400));
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
      _ensureNotCancelled();

      // Sleep ONLY — power-down after the first take was preventing reliable
      // BLE wake (ads/bond OK once, then Android 133 on the next KAYIT).
      final sleeping = _device;
      try {
        await sleepCamera();
      } catch (e) {
        debugPrint('Sleep after stop: $e');
      }

      if (sleeping != null) {
        try {
          await sleeping.connectionState
              .firstWhere((s) => s == BluetoothConnectionState.disconnected)
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          if (_cancelRequested) throw const GoProCancelledException();
          try {
            await sleeping.disconnect();
          } catch (_) {}
        }
      }

      await _delayCancellable(const Duration(milliseconds: 400));
      await _teardownLink();
      _lastSleepAt = DateTime.now();
      _resetSessionLocal();
      return;
    }

    try {
      await wakeAndRecord();
    } catch (e) {
      if (e is GoProCancelledException || _cancelRequested) {
        _resetSessionLocal();
        throw const GoProCancelledException();
      }
      _resetSessionLocal(error: _friendlyError(e));
      rethrow;
    }
  }

  /// Press-path: fresh scan → connect → shutter.
  ///
  /// After sleep, each retry must re-scan. Reusing a pre-sleep scan result is
  /// a common source of Android GATT 133 on the second wake.
  Future<void> wakeAndRecord() async {
    _error = null;
    await ensurePrefsLoaded();
    await ensureAdapterOn();
    _ensureNotCancelled();

    if (isConnected && _commandReq != null) {
      await _burstStartShutter();
      return;
    }

    try {
      await stopScan();
    } catch (_) {}

    await _awaitPostSleepCooldown();

    Object? lastError;
    const attempts = 2;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      _ensureNotCancelled();
      try {
        final target = await _scanForFreshGoPro(
          timeout: Duration(seconds: attempt == 1 ? 3 : 5),
        );
        await connect(
          target,
          retries: 2,
          fastRecord: true,
          shutterOnConnect: true,
        );
        return;
      } catch (e) {
        if (e is GoProCancelledException || _cancelRequested) rethrow;
        lastError = e;
        debugPrint('wakeAndRecord attempt $attempt/$attempts: $e');
        _sessionRecording = false;
        status = const GoProCameraStatus();
        await _teardownLink(keepState: true);
        await _delayCancellable(Duration(milliseconds: 400 * attempt));
      }
    }

    _error = _friendlyError(lastError);
    _setState(GoProConnectionState.error);
    notifyListeners();
    throw StateError(_error!);
  }

  /// Low-latency scan; prefers last camera id, otherwise first GoPro seen.
  Future<GoProDeviceInfo> _scanForFreshGoPro({
    required Duration timeout,
  }) async {
    discovered.clear();
    _setState(GoProConnectionState.scanning);
    _ensureNotCancelled();

    final done = Completer<GoProDeviceInfo>();
    _activeScanCompleter = done;
    GoProDeviceInfo? fallback;
    await _scanSub?.cancel();

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    final controlGuid = Guid(GoProUuids.controlService);

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      if (_cancelRequested) return;
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
        final id = r.device.remoteId.str;
        final knownId = _isKnownRemoteId(id);
        final preferred =
            preferredRemoteId != null && id == preferredRemoteId;
        if (!nameMatch && !hasGoProService && !knownId) continue;

        final info = GoProDeviceInfo(
          device: r.device,
          name: name.isNotEmpty ? name : (_savedNameFor(id) ?? 'GoPro'),
          remoteId: id,
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

        // Prefer selected saved camera; otherwise first GoPro wins.
        if (preferred || knownId || !done.isCompleted) {
          if (preferred || knownId || fallback == null) {
            fallback = info;
          }
          if (preferred) {
            if (!done.isCompleted) done.complete(info);
            unawaited(FlutterBluePlus.stopScan());
            return;
          }
          if (!done.isCompleted && (knownId || nameMatch || hasGoProService)) {
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

    // Narrow scan to selected camera when known — much faster on Android.
    final preferId = preferredRemoteId;
    if (preferId != null) {
      await beginScan(remoteIds: [preferId]);
      try {
        return await done.future.timeout(timeout);
      } on TimeoutException {
        if (discovered.isNotEmpty) return discovered.first;
        // Fall through to wide scan.
        await FlutterBluePlus.stopScan();
      } on GoProCancelledException {
        rethrow;
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
      if (identical(_activeScanCompleter, done)) {
        _activeScanCompleter = null;
      }
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
          await c.setNotifyValue(true, timeout: minimal ? 1 : 3);
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
      preferWithoutResponse: true,
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
      await _bleWrite(char, bytes, preferWithoutResponse: true, timeoutSec: 2);
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
    if (e is GoProCancelledException) return 'İptal edildi';
    final text = e?.toString() ?? 'Bilinmeyen hata';
    if (text.contains('İptal edildi')) return 'İptal edildi';
    if (text.contains('133') ||
        text.contains('ANDROID_SPECIFIC_ERROR') ||
        text.contains('GATT_ERROR')) {
      return 'Bluetooth bağlantısı kurulamadı (Android 133). '
          'GoPro’da Preferences → Connections → Devices ekranından çıkıp '
          'ana ekrana dön. Quik kapalı olsun. Telefonda Bluetooth kapat-aç, '
          'kamerayı kapat-aç, X ile iptal edip tekrar KAYIT.';
    }
    if (text.contains('writeCharacteristic') ||
        text.contains('Timed out') ||
        text.contains('zaman aşımı') ||
        text.contains('gönderilemedi') ||
        text.contains('eşleştirmeyi')) {
      return 'Kamera komutu başarısız. GoPro’yu aç, telefonda Bluetooth '
          'eşleştirme isteğini onayla, sonra tekrar KAYIT’a bas.';
    }
    return text;
  }

  bool _isKnownRemoteId(String remoteId) {
    return _savedDevices.any((d) => d.remoteId == remoteId);
  }

  String? _savedNameFor(String remoteId) {
    for (final d in _savedDevices) {
      if (d.remoteId == remoteId) return d.name;
    }
    return null;
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
