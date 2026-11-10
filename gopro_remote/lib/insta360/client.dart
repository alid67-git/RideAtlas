import 'dart:async';
import 'dart:convert';

import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    hide CharacteristicProperties;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'protocol.dart';
import 'uuids.dart';

enum _InstaLinkMode { none, peripheral, central }

/// Insta360 remote control.
///
/// Prefers Architecture B (phone = central → camera `be80`) when the camera is
/// already awake — this is the reliable X4 shutter path. Falls back to
/// GPS-Remote emulation (phone = peripheral) to wake a sleeping camera.
class Insta360Client extends ChangeNotifier {
  Insta360ConnectionState _state = Insta360ConnectionState.disconnected;
  Insta360ConnectionState get state => _state;

  String? _error;
  String? get error => _error;

  String? connectedName;
  Insta360CameraStatus status = const Insta360CameraStatus();

  bool _sessionRecording = false;
  bool get isSessionRecording => _sessionRecording || status.encoding;

  _InstaLinkMode _mode = _InstaLinkMode.none;

  String? _peripheralDeviceId;
  BluetoothDevice? _centralDevice;
  BluetoothCharacteristic? _be81;
  StreamSubscription<List<int>>? _be82Sub;
  StreamSubscription<BluetoothConnectionState>? _centralConnSub;
  int _directSeq = 1;

  bool get isConnected =>
      _state == Insta360ConnectionState.connected &&
      (_mode == _InstaLinkMode.peripheral && _peripheralDeviceId != null ||
          _mode == _InstaLinkMode.central && _centralDevice != null);

  bool get isSupported => true;

  final List<SavedInsta360Device> _savedDevices = [];
  List<SavedInsta360Device> get savedDevices =>
      List.unmodifiable(_savedDevices);

  String? _selectedSerial;
  String? get selectedSerial => _selectedSerial;

  SavedInsta360Device? get selectedDevice {
    final serial = _selectedSerial;
    if (serial == null) return null;
    for (final d in _savedDevices) {
      if (d.serial == serial) return d;
    }
    return null;
  }

  String? get preferredName => selectedDevice?.name ?? connectedName;

  final List<Insta360ScanHit> discovered = [];

  static const _prefsSavedKey = 'insta360_saved_devices_v1';
  static const _prefsSelectedKey = 'insta360_selected_serial';
  static const _prefsGpsRemotePairedKey = 'insta360_gps_remote_paired_v1';

  bool _prefsLoaded = false;
  bool _gattReady = false;
  bool _cancelRequested = false;
  bool get isCancelRequested => _cancelRequested;

  /// True after the camera has connected to us as a GPS Remote at least once.
  bool _gpsRemotePaired = false;
  bool get gpsRemotePaired => _gpsRemotePaired;

  /// X4 can only power-off over the GPS Remote (ce82) link.
  bool get canPowerOff =>
      (_mode == _InstaLinkMode.peripheral && isConnected) || _gpsRemotePaired;

  /// Live instruction shown while waiting (pairing / wake / power-off).
  String? actionHint;

  int _buttonSeq = 0;
  int _sessionEpoch = 0;
  Timer? _gpsKeepalive;
  Completer<void>? _serviceAddCompleter;
  Completer<void>? _connectedCompleter;
  StreamSubscription<List<ScanResult>>? _scanSub;

  void beginOperation() {
    _cancelRequested = false;
  }

  Future<void> cancelOperation() async {
    _cancelRequested = true;
    _sessionEpoch++;
    _error = null;
    notifyListeners();
    try {
      await stopScan();
    } catch (_) {}
    final waiting = _connectedCompleter;
    if (waiting != null && !waiting.isCompleted) {
      waiting.completeError(const Insta360CancelledException());
    }
    await _teardown(keepSaved: true);
  }

  void _ensureNotCancelled() {
    if (_cancelRequested) throw const Insta360CancelledException();
  }

  Future<void> ensurePrefsLoaded() async {
    if (_prefsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsSavedKey);
    _savedDevices.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final d = SavedInsta360Device.fromJson(item);
            if (d.serial.length == 6) _savedDevices.add(d);
          } else if (item is Map) {
            final d = SavedInsta360Device.fromJson(
              Map<String, dynamic>.from(item),
            );
            if (d.serial.length == 6) _savedDevices.add(d);
          }
        }
      } catch (_) {}
    }
    _selectedSerial = prefs.getString(_prefsSelectedKey);
    _gpsRemotePaired = prefs.getBool(_prefsGpsRemotePairedKey) ?? false;
    if (_selectedSerial != null &&
        !_savedDevices.any((d) => d.serial == _selectedSerial)) {
      _selectedSerial =
          _savedDevices.isEmpty ? null : _savedDevices.first.serial;
    } else if (_selectedSerial == null && _savedDevices.isNotEmpty) {
      _selectedSerial = _savedDevices.first.serial;
    }
    _prefsLoaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsSavedKey,
      jsonEncode(_savedDevices.map((d) => d.toJson()).toList()),
    );
    if (_selectedSerial == null) {
      await prefs.remove(_prefsSelectedKey);
    } else {
      await prefs.setString(_prefsSelectedKey, _selectedSerial!);
    }
    await prefs.setBool(_prefsGpsRemotePairedKey, _gpsRemotePaired);
  }

  Future<void> _markGpsRemotePaired() async {
    if (_gpsRemotePaired) return;
    _gpsRemotePaired = true;
    await _persist();
    notifyListeners();
  }

  void _setHint(String? hint) {
    actionHint = hint;
    notifyListeners();
  }

  Future<void> selectDevice(SavedInsta360Device device) async {
    await ensurePrefsLoaded();
    _selectedSerial = device.serial;
    await _persist();
    notifyListeners();
  }

  Future<void> forgetDevice(SavedInsta360Device device) async {
    await ensurePrefsLoaded();
    _savedDevices.removeWhere((d) => d.serial == device.serial);
    if (_selectedSerial == device.serial) {
      _selectedSerial =
          _savedDevices.isEmpty ? null : _savedDevices.first.serial;
    }
    await _persist();
    notifyListeners();
  }

  Future<SavedInsta360Device> saveFromScan(Insta360ScanHit hit) async {
    await ensurePrefsLoaded();
    final existing = _savedDevices.indexWhere((d) => d.serial == hit.serial);
    final device = SavedInsta360Device(
      serial: hit.serial,
      name: hit.name,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
      remoteId: hit.remoteId,
    );
    if (existing >= 0) {
      _savedDevices[existing] = device;
    } else {
      _savedDevices.add(device);
    }
    _selectedSerial = device.serial;
    await _persist();
    notifyListeners();
    return device;
  }

  Future<SavedInsta360Device> saveManual({
    required String nameOrSerial,
  }) async {
    await ensurePrefsLoaded();
    final serial = extractInstaSerial(nameOrSerial);
    if (serial == null || serial.length != 6) {
      throw StateError(
        'Geçerli Insta360 adı veya 6 karakter seri gir '
        '(ör. "X4 34UQG5" veya "34UQG5").',
      );
    }
    final name = nameOrSerial.trim().length > 6
        ? nameOrSerial.trim()
        : 'Insta360 $serial';
    final device = SavedInsta360Device(
      serial: serial,
      name: name,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final existing = _savedDevices.indexWhere((d) => d.serial == serial);
    if (existing >= 0) {
      _savedDevices[existing] = device;
    } else {
      _savedDevices.add(device);
    }
    _selectedSerial = serial;
    await _persist();
    notifyListeners();
    return device;
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 8)}) async {
    await ensurePrefsLoaded();
    discovered.clear();
    notifyListeners();
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      var changed = false;
      for (final r in results) {
        final name = r.advertisementData.advName.trim().isNotEmpty
            ? r.advertisementData.advName.trim()
            : (r.device.platformName.trim().isNotEmpty
                ? r.device.platformName.trim()
                : '');
        if (name.isEmpty || !looksLikeInsta360Name(name)) continue;
        final serial = extractInstaSerial(name);
        if (serial == null) continue;
        final id = r.device.remoteId.str;
        final idx = discovered.indexWhere((d) => d.remoteId == id);
        final hit = Insta360ScanHit(
          name: name,
          remoteId: id,
          serial: serial,
          rssi: r.rssi,
        );
        if (idx < 0) {
          discovered.add(hit);
          changed = true;
        } else if (discovered[idx].rssi != r.rssi) {
          discovered[idx] = hit;
          changed = true;
        }
      }
      if (changed) notifyListeners();
    });
    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: true,
    );
    await Future<void>.delayed(timeout);
    await stopScan();
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
  }

  /// Initialize GATT server. Must call [BlePeripheral.initialize] *before*
  /// any support checks — otherwise `isSupported` always returns false
  /// (adapter is null until initialize).
  Future<void> _ensureGattServer() async {
    if (_gattReady) return;

    try {
      await BlePeripheral.initialize();
    } on PlatformException catch (e) {
      throw StateError(
        'BLE kumanda (peripheral) açılamadı: ${e.message ?? e.code}',
      );
    } catch (e) {
      throw StateError('BLE kumanda (peripheral) açılamadı: $e');
    }

    // Optional post-init probe; initialize already validates advertiser/GATT.
    try {
      final supported = await BlePeripheral.isSupported();
      if (!supported) {
        throw StateError('Bu telefonda BLE reklamı (peripheral) yok.');
      }
    } on PlatformException catch (e) {
      throw StateError(
        'Bu telefonda BLE reklamı desteklenmiyor: ${e.message ?? e.code}',
      );
    }

    BlePeripheral.setServiceAddedCallback((serviceId, error) {
      final c = _serviceAddCompleter;
      if (c == null || c.isCompleted) return;
      if (error != null && error.isNotEmpty) {
        c.completeError(StateError('GATT servisi eklenemedi: $error'));
      } else {
        c.complete();
      }
    });

    BlePeripheral.setConnectionStateChangeCallback((deviceId, connected) {
      if (connected) {
        // Ignore stale connects after cancel/teardown or while on central path.
        if (_cancelRequested ||
            (_state != Insta360ConnectionState.advertising &&
                _state != Insta360ConnectionState.connecting &&
                _mode != _InstaLinkMode.peripheral)) {
          return;
        }
        _peripheralDeviceId = deviceId;
        _mode = _InstaLinkMode.peripheral;
        connectedName = selectedDevice?.name ?? 'Insta360';
        _buttonSeq = 0;
        unawaited(_markGpsRemotePaired());
        _setHint(null);
        _setState(Insta360ConnectionState.connected);
        _startGpsKeepalive();
        final waiting = _connectedCompleter;
        if (waiting != null && !waiting.isCompleted) {
          waiting.complete();
        }
      } else if (_peripheralDeviceId == deviceId ||
          _peripheralDeviceId == null) {
        if (_mode == _InstaLinkMode.peripheral) {
          _stopGpsKeepalive();
          _peripheralDeviceId = null;
          _mode = _InstaLinkMode.none;
          _sessionRecording = false;
          if (_state != Insta360ConnectionState.disconnected) {
            _setState(Insta360ConnectionState.disconnected);
          }
        }
      }
    });

    BlePeripheral.setWriteRequestCallback(
        (deviceId, characteristicId, offset, value) {
      if (value == null || value.isEmpty) {
        return WriteRequestResult(status: 0);
      }
      final id = characteristicId.toLowerCase();
      if (id.contains('ce81')) {
        final parsed = parseCameraWrite(value);
        if (parsed != null) {
          var next = status;
          if (parsed.encoding != null) {
            next = next.copyWith(
              encoding: parsed.encoding,
              encodingDurationSec: parsed.encodingDurationSec,
              displayText: parsed.displayText,
            );
            if (parsed.encoding == true) {
              _sessionRecording = true;
            } else if (parsed.encoding == false &&
                parsed.displayText != null &&
                !parsed.displayText!.contains(':')) {
              _sessionRecording = false;
            }
          } else if (parsed.displayText != null) {
            next = next.copyWith(displayText: parsed.displayText);
          }
          if (parsed.serial != null && connectedName == null) {
            connectedName = 'Insta360 ${parsed.serial}';
          }
          status = next;
          notifyListeners();
        }
      }
      return WriteRequestResult(status: 0);
    });

    BlePeripheral.setReadRequestCallback(
        (deviceId, characteristicId, offset, value) {
      final id = characteristicId.toLowerCase();
      if (id.contains('ce83')) {
        return ReadRequestResult(value: Uint8List.fromList([0x02, 0x01]));
      }
      if (id.contains('ffd3')) {
        return ReadRequestResult(
          value: Uint8List.fromList([0x01, 0x90, 0x1e, 0x30]),
        );
      }
      if (id.contains('ffd4')) {
        return ReadRequestResult(
          value: Uint8List.fromList([0x01, 0x20, 0x00, 0x18]),
        );
      }
      if (id.contains('ffd1')) {
        return ReadRequestResult(
          value: Uint8List.fromList(utf8.encode('Insta360 GPS Remote')),
        );
      }
      if (id.contains('ffd2')) {
        return ReadRequestResult(
          value: Uint8List.fromList(utf8.encode('1.0.0')),
        );
      }
      return ReadRequestResult(value: Uint8List(0));
    });

    await BlePeripheral.clearServices();

    await _addService(BleService(
      uuid: InstaUuids.serviceCe80,
      primary: true,
      characteristics: [
        BleCharacteristic(
          uuid: InstaUuids.charCe81,
          properties: [
            CharacteristicProperties.write.index,
            CharacteristicProperties.writeWithoutResponse.index,
          ],
          permissions: [AttributePermissions.writeable.index],
        ),
        BleCharacteristic(
          uuid: InstaUuids.charCe82,
          properties: [
            CharacteristicProperties.notify.index,
            CharacteristicProperties.indicate.index,
          ],
          permissions: [AttributePermissions.readable.index],
          descriptors: [
            BleDescriptor(
              uuid: '00002902-0000-1000-8000-00805f9b34fb',
              permissions: [
                AttributePermissions.readable.index,
                AttributePermissions.writeable.index,
              ],
              value: Uint8List.fromList([0x00, 0x00]),
            ),
          ],
        ),
        BleCharacteristic(
          uuid: InstaUuids.charCe83,
          properties: [CharacteristicProperties.read.index],
          permissions: [AttributePermissions.readable.index],
          value: Uint8List.fromList([0x02, 0x01]),
        ),
      ],
    ));

    await _addService(BleService(
      uuid: InstaUuids.serviceD0ff,
      primary: true,
      characteristics: [
        BleCharacteristic(
          uuid: InstaUuids.charFfd1,
          properties: [CharacteristicProperties.read.index],
          permissions: [AttributePermissions.readable.index],
          value: Uint8List.fromList(utf8.encode('Insta360 GPS Remote')),
        ),
        BleCharacteristic(
          uuid: InstaUuids.charFfd2,
          properties: [CharacteristicProperties.read.index],
          permissions: [AttributePermissions.readable.index],
          value: Uint8List.fromList(utf8.encode('1.0.0')),
        ),
        BleCharacteristic(
          uuid: InstaUuids.charFfd3,
          properties: [CharacteristicProperties.read.index],
          permissions: [AttributePermissions.readable.index],
          value: Uint8List.fromList([0x01, 0x90, 0x1e, 0x30]),
        ),
        BleCharacteristic(
          uuid: InstaUuids.charFfd4,
          properties: [CharacteristicProperties.read.index],
          permissions: [AttributePermissions.readable.index],
          value: Uint8List.fromList([0x01, 0x20, 0x00, 0x18]),
        ),
      ],
    ));

    _gattReady = true;
  }

  Future<void> _addService(BleService service) async {
    _serviceAddCompleter = Completer<void>();
    await BlePeripheral.addService(service);
    await _serviceAddCompleter!.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw StateError('GATT servisi zaman aşımı'),
    );
  }

  Future<void> _startWakeAdvertising(String serial) async {
    final manuf = ManufacturerData(
      manufacturerId: InstaUuids.appleCompanyId,
      data: buildOrbitWakeManufacturerData(serial),
    );

    try {
      await BlePeripheral.stopAdvertising();
    } catch (_) {}

    try {
      await BlePeripheral.startAdvertising(
        services: const [],
        localName: 'Insta360 GPS Remote',
        manufacturerData: manuf,
      );
    } catch (_) {
      await BlePeripheral.startAdvertising(
        services: const [],
        manufacturerData: manuf,
      );
    }
  }

  Future<void> _startDiscoverableAdvertising() async {
    try {
      await BlePeripheral.stopAdvertising();
    } catch (_) {}
    await BlePeripheral.startAdvertising(
      services: [InstaUuids.serviceCe80],
      localName: 'Insta360 GPS Remote',
    );
  }

  Future<void> _notifyButton(Uint8List frame) async {
    if (_peripheralDeviceId == null) {
      throw StateError('Insta360 kumanda bağlantısı yok (ce82).');
    }
    await BlePeripheral.updateCharacteristic(
      characteristicId: InstaUuids.charCe82,
      value: frame,
      deviceId: _peripheralDeviceId,
    );
  }

  void _startGpsKeepalive() {
    _stopGpsKeepalive();
    // Real GPS remotes stream ~10 Hz; silence makes X4 drop the link.
    _gpsKeepalive = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_mode != _InstaLinkMode.peripheral || _peripheralDeviceId == null) {
        return;
      }
      unawaited(() async {
        try {
          await BlePeripheral.updateCharacteristic(
            characteristicId: InstaUuids.charCe82,
            value: buildVoidGpsKeepaliveFrame(),
            deviceId: _peripheralDeviceId,
          );
        } catch (_) {}
      }());
    });
  }

  void _stopGpsKeepalive() {
    _gpsKeepalive?.cancel();
    _gpsKeepalive = null;
  }

  int _nextButtonSeq() {
    final sn = _buttonSeq;
    _buttonSeq = (_buttonSeq + 2) & 0xff;
    return sn;
  }

  int _nextDirectSeq() {
    final sn = _directSeq;
    _directSeq = _directSeq >= 254 ? 1 : _directSeq + 1;
    return sn;
  }

  Future<void> _sendPeripheralShutter() async {
    await _notifyButton(shutterClickFrame(_nextButtonSeq()));
  }

  Future<void> _sendPeripheralPowerOffHold({
    Duration duration = const Duration(milliseconds: 3000),
  }) async {
    final end = DateTime.now().add(duration);
    while (DateTime.now().isBefore(end)) {
      _ensureNotCancelled();
      await _notifyButton(powerHoldFrame(_nextButtonSeq()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> _writeDirect(int command) async {
    final char = _be81;
    if (char == null) throw StateError('Insta360 be81 yok');
    final frame = buildHeader16Command(
      command: command,
      sequence: _nextDirectSeq(),
    );
    try {
      await char.write(frame, withoutResponse: false, timeout: 5);
    } catch (_) {
      await char.write(frame, withoutResponse: true, timeout: 3);
    }
  }

  String _errText(Object e) {
    var s = e.toString().trim();
    if (s.startsWith('Bad state: ')) s = s.substring('Bad state: '.length);
    if (s.startsWith('StateError: ')) s = s.substring('StateError: '.length);
    if (s.startsWith('Exception: ')) s = s.substring('Exception: '.length);
    return s;
  }

  Future<void> _dropCentralLink() async {
    await _be82Sub?.cancel();
    _be82Sub = null;
    await _centralConnSub?.cancel();
    _centralConnSub = null;
    try {
      await _centralDevice?.disconnect();
    } catch (_) {}
    _centralDevice = null;
    _be81 = null;
    if (_mode == _InstaLinkMode.central) {
      _mode = _InstaLinkMode.none;
    }
  }

  Future<void> _advertiseAsGpsRemote({
    required SavedInsta360Device selected,
    required bool includeOrbitWake,
  }) async {
    if (includeOrbitWake) {
      final manuf = ManufacturerData(
        manufacturerId: InstaUuids.appleCompanyId,
        data: buildOrbitWakeManufacturerData(selected.serial),
      );
      try {
        await BlePeripheral.startAdvertising(
          services: [InstaUuids.serviceCe80],
          localName: 'Insta360 GPS Remote',
          manufacturerData: manuf,
        );
        return;
      } catch (_) {}
    }
    try {
      await _startDiscoverableAdvertising();
    } catch (_) {
      if (includeOrbitWake) {
        await _startWakeAdvertising(selected.serial);
      } else {
        rethrow;
      }
    }
  }

  /// Wait for the camera to connect to our GPS Remote GATT (pairing or reconnect).
  Future<void> _awaitGpsRemoteLink(
    SavedInsta360Device selected, {
    required Duration timeout,
    required String hint,
  }) async {
    await _ensureGattServer();
    _ensureNotCancelled();
    _connectedCompleter = Completer<void>();
    final linkFuture = _connectedCompleter!.future;
    _mode = _InstaLinkMode.peripheral;
    _setState(Insta360ConnectionState.advertising);
    connectedName = selected.name;
    _setHint(hint);

    final deadline = DateTime.now().add(timeout);
    var orbit = true;
    while (DateTime.now().isBefore(deadline)) {
      _ensureNotCancelled();
      if (isConnected && _peripheralDeviceId != null) {
        _setHint(null);
        return;
      }
      try {
        await BlePeripheral.stopAdvertising();
      } catch (_) {}
      await _advertiseAsGpsRemote(selected: selected, includeOrbitWake: orbit);
      orbit = !orbit;

      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      final slice = remaining < const Duration(seconds: 5)
          ? remaining
          : const Duration(seconds: 5);
      try {
        await linkFuture.timeout(slice);
        _setHint(null);
        return;
      } on TimeoutException {
        // Re-advertise and keep waiting on the same completer.
      }
    }
    if (isConnected && _peripheralDeviceId != null) {
      _setHint(null);
      return;
    }
    throw StateError(
      'GPS Remote bağlanmadı (${selected.serial}).\n'
      'X4 açıkken: Ayarlar → Bluetooth → GPS Remote / Kumanda → '
      '“Insta360 GPS Remote” seç. Bir kez yeter.',
    );
  }

  /// Guided one-time pairing: advertise until camera connects from its menu.
  Future<void> pairGpsRemote({
    Duration timeout = const Duration(seconds: 75),
  }) async {
    await ensurePrefsLoaded();
    final selected = selectedDevice;
    if (selected == null) {
      throw StateError('Önce bir Insta360 kaydet (Kameralar).');
    }
    await stopScan();
    await _dropCentralLink();
    try {
      await BlePeripheral.stopAdvertising();
    } catch (_) {}

    await _awaitGpsRemoteLink(
      selected,
      timeout: timeout,
      hint:
          'X4 listesinde “Insta360 GPS Remote” seç (telefon adını değiştirme)',
    );
    _ensureNotCancelled();
    await _markGpsRemotePaired();
    _setHint(null);
    // Brief screen wake so user sees the link; leave connected for power/record.
    try {
      await _notifyButton(powerClickFrame(_nextButtonSeq()));
    } catch (_) {}
  }

  /// X4 has no reliable be81 power-off; shut down via GPS-remote power-hold.
  Future<void> _powerOffViaGpsRemote(SavedInsta360Device selected) async {
    await _dropCentralLink();
    await stopScan();
    try {
      await BlePeripheral.stopAdvertising();
    } catch (_) {}

    final timeout = _gpsRemotePaired
        ? const Duration(seconds: 28)
        : const Duration(seconds: 70);
    await _awaitGpsRemoteLink(
      selected,
      timeout: timeout,
      hint: _gpsRemotePaired
          ? 'GPS Remote bekleniyor → kapatılıyor…'
          : 'Kapatmak için X4’te “Insta360 GPS Remote” seç (bir kez)',
    );

    _ensureNotCancelled();
    await _markGpsRemotePaired();
    _startGpsKeepalive();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _setHint('Kapatılıyor (power-hold)…');
    await _sendPeripheralPowerOffHold();
    _setHint(null);
  }

  Future<void> _powerOffBestEffort(SavedInsta360Device selected) async {
    if (_mode == _InstaLinkMode.peripheral && isConnected) {
      _setHint('Kapatılıyor (power-hold)…');
      await _sendPeripheralPowerOffHold();
      _setHint(null);
      return;
    }
    if (_mode == _InstaLinkMode.central && isConnected) {
      await _powerOffViaGpsRemote(selected);
      return;
    }
    throw StateError('Kapatmak için önce Bağlan.');
  }

  Future<BluetoothDevice?> _scanForCamera(
    SavedInsta360Device selected, {
    required Duration timeout,
  }) async {
    await stopScan();
    final completer = Completer<BluetoothDevice>();
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.trim().isNotEmpty
            ? r.advertisementData.advName.trim()
            : r.device.platformName.trim();
        final serial = extractInstaSerial(name);
        final idMatch = selected.remoteId != null &&
            selected.remoteId!.isNotEmpty &&
            r.device.remoteId.str == selected.remoteId;
        if (idMatch ||
            serial == selected.serial ||
            name.toUpperCase().contains(selected.serial)) {
          if (!completer.isCompleted) completer.complete(r.device);
          break;
        }
      }
    });
    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: true,
    );
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      await stopScan();
    }
  }

  Future<void> _finishCentralSession(
    BluetoothDevice target,
    SavedInsta360Device selected,
  ) async {
    _ensureNotCancelled();
    _setState(Insta360ConnectionState.connecting);
    connectedName = selected.name;

    try {
      await target.disconnect();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 250));

    await target.connect(
      autoConnect: false,
      timeout: const Duration(seconds: 20),
      mtu: null,
    );
    _ensureNotCancelled();

    final services = await target.discoverServices();
    BluetoothCharacteristic? be81;
    BluetoothCharacteristic? be82;
    for (final s in services) {
      final su = s.uuid.str128.toLowerCase();
      if (!su.contains('be80')) continue;
      for (final c in s.characteristics) {
        final id = c.uuid.str128.toLowerCase();
        if (id.contains('be81')) be81 = c;
        if (id.contains('be82')) be82 = c;
      }
    }
    if (be81 == null) {
      try {
        await target.disconnect();
      } catch (_) {}
      throw StateError(
        'Kamerada be80 kumanda servisi yok. Insta uygulamasını kapatıp tekrar dene.',
      );
    }

    _be81 = be81;
    _centralDevice = target;
    _mode = _InstaLinkMode.central;
    _directSeq = 1;
    final epoch = _sessionEpoch;

    await _centralConnSub?.cancel();
    _centralConnSub = target.connectionState.listen((s) {
      if (epoch != _sessionEpoch) return;
      if (s == BluetoothConnectionState.disconnected &&
          _mode == _InstaLinkMode.central) {
        _centralDevice = null;
        _be81 = null;
        _mode = _InstaLinkMode.none;
        _sessionRecording = false;
        _setState(Insta360ConnectionState.disconnected);
      }
    });

    if (be82 != null) {
      try {
        await be82.setNotifyValue(true);
        await _be82Sub?.cancel();
        _be82Sub = be82.onValueReceived.listen((_) {});
      } catch (_) {}
    }

    final idx = _savedDevices.indexWhere((d) => d.serial == selected.serial);
    if (idx >= 0) {
      _savedDevices[idx] = selected.copyWith(remoteId: target.remoteId.str);
      unawaited(_persist());
    }

    _setState(Insta360ConnectionState.connected);
  }

  /// Awake camera: quick scan. Sleeping: ORBIT wake advert + scan together.
  Future<void> _connectCentral(SavedInsta360Device selected) async {
    _setState(Insta360ConnectionState.scanning);
    discovered.clear();
    notifyListeners();

    var target = await _scanForCamera(
      selected,
      timeout: const Duration(seconds: 4),
    );

    if (target == null) {
      _ensureNotCancelled();
      _setState(Insta360ConnectionState.advertising);
      notifyListeners();
      // Sleeping X4 scans for ORBIT; keep beaconing while we listen for be80.
      try {
        await _ensureGattServer();
      } catch (_) {}
      await _startWakeAdvertising(selected.serial);

      final wakeUntil = DateTime.now().add(const Duration(seconds: 22));
      while (target == null && DateTime.now().isBefore(wakeUntil)) {
        _ensureNotCancelled();
        try {
          await _startWakeAdvertising(selected.serial);
        } catch (_) {}
        target = await _scanForCamera(
          selected,
          timeout: const Duration(seconds: 5),
        );
      }

      try {
        await BlePeripheral.stopAdvertising();
      } catch (_) {}
    }

    if (target == null) {
      throw StateError(
        'Kamera BLE’de görünmüyor. X4 uyku/kapalı olabilir. '
        'Bluetooth Wakeup açıkken Bağlan tekrar dene; tamamen kapalıysa elle aç, '
        'Insta uygulamasını kapat.',
      );
    }

    await _finishCentralSession(target, selected);
  }

  Future<void> _connectPeripheral(SavedInsta360Device selected) async {
    await _ensureGattServer();
    _ensureNotCancelled();

    _setState(Insta360ConnectionState.advertising);
    connectedName = selected.name;
    _connectedCompleter = Completer<void>();
    _mode = _InstaLinkMode.peripheral;

    final manuf = ManufacturerData(
      manufacturerId: InstaUuids.appleCompanyId,
      data: buildOrbitWakeManufacturerData(selected.serial),
    );
    try {
      await BlePeripheral.startAdvertising(
        services: [InstaUuids.serviceCe80],
        localName: 'Insta360 GPS Remote',
        manufacturerData: manuf,
      );
    } catch (_) {
      await _startWakeAdvertising(selected.serial);
    }

    unawaited(Future<void>.delayed(const Duration(seconds: 4), () async {
      if (_cancelRequested || isConnected) return;
      try {
        await _startDiscoverableAdvertising();
        await Future<void>.delayed(const Duration(seconds: 3));
        if (_cancelRequested || isConnected) return;
        await _startWakeAdvertising(selected.serial);
      } catch (_) {}
    }));

    await _connectedCompleter!.future.timeout(
      const Duration(seconds: 28),
      onTimeout: () {
        throw StateError(
          'GPS Remote bağlanmadı (${selected.serial}). '
          'X4’te GPS Remote eşleştirmesini kontrol et.',
        );
      },
    );
    _ensureNotCancelled();
    try {
      await _notifyButton(powerClickFrame(_nextButtonSeq()));
    } catch (_) {}
  }

  Future<void> toggleConnectSleep() async {
    await ensurePrefsLoaded();
    _error = null;

    if (isConnected || _sessionRecording) {
      final selected = selectedDevice;
      _setState(Insta360ConnectionState.connecting);
      Object? powerError;
      try {
        if (selected != null) {
          await _powerOffBestEffort(selected);
        } else if (_mode == _InstaLinkMode.peripheral && isConnected) {
          await _sendPeripheralPowerOffHold();
        }
      } catch (e) {
        powerError = e;
        _error = _errText(e);
      }
      _sessionRecording = false;
      status = const Insta360CameraStatus();
      await _teardown(keepSaved: true);
      if (powerError != null) {
        throw StateError(_errText(powerError));
      }
      return;
    }

    final selected = selectedDevice;
    if (selected == null) {
      throw StateError(
        'Önce bir Insta360 kaydet (Kameralar → ekle). '
        'Uyandırma için kamera adındaki 6 karakter seri gerekir.',
      );
    }

    await stopScan();

    // Once GPS Remote has been paired, prefer that link (needed for power-off).
    if (_gpsRemotePaired) {
      Object? remoteError;
      try {
        await _connectPeripheral(selected);
        return;
      } catch (e) {
        remoteError = e;
        await _teardown(keepSaved: true);
        _ensureNotCancelled();
      }
      try {
        await _connectCentral(selected);
        return;
      } catch (e) {
        await _teardown(keepSaved: true);
        throw StateError(
          'Bağlantı başarısız.\n'
          'GPS Remote: ${_errText(remoteError)}\n'
          'Doğrudan (be80): ${_errText(e)}',
        );
      }
    }

    // Unpaired: central for record; peripheral as fallback / first pairing.
    Object? centralError;
    try {
      await _connectCentral(selected);
      return;
    } catch (e) {
      centralError = e;
      await _teardown(keepSaved: true);
      _ensureNotCancelled();
    }

    try {
      await _connectPeripheral(selected);
    } catch (e) {
      await _teardown(keepSaved: true);
      throw StateError(
        'Bağlantı başarısız.\n'
        'Doğrudan (be80): ${_errText(centralError)}\n'
        'GPS Remote: ${_errText(e)}',
      );
    }
  }

  Future<void> toggleRecording() async {
    await ensurePrefsLoaded();
    _error = null;

    if (!isConnected) {
      await toggleConnectSleep();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    _ensureNotCancelled();
    if (!isConnected) {
      throw StateError('Insta360 bağlı değil');
    }

    final selected = selectedDevice;
    final wasRecording = isSessionRecording;
    final modeAtStart = _mode;

    if (modeAtStart == _InstaLinkMode.peripheral) {
      await _sendPeripheralShutter();
    } else {
      await _writeDirect(
        wasRecording ? InstaDirectCode.stopCapture : InstaDirectCode.startCapture,
      );
    }

    _sessionRecording = !wasRecording;
    status = status.copyWith(
      encoding: _sessionRecording,
      encodingDurationSec: _sessionRecording ? 0 : status.encodingDurationSec,
    );
    notifyListeners();

    if (!wasRecording) return;

    // Stop then power-off (GPS Remote hold — be81 cannot shut X4 down).
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _ensureNotCancelled();
    Object? powerError;
    try {
      if (selected != null) {
        await _powerOffBestEffort(selected);
      } else if (modeAtStart == _InstaLinkMode.peripheral) {
        await _sendPeripheralPowerOffHold();
      } else {
        throw StateError(
          'Kayıt durdu ama kapatılamadı (kayıtlı kamera yok).',
        );
      }
    } catch (e) {
      powerError = e;
    }
    await _teardown(keepSaved: true);
    if (powerError != null) {
      throw StateError(
        'Kayıt durdu ama kapatılamadı. ${_errText(powerError)}',
      );
    }
  }

  Future<void> _teardown({required bool keepSaved}) async {
    _sessionEpoch++;
    _stopGpsKeepalive();
    _setHint(null);
    try {
      await BlePeripheral.stopAdvertising();
    } catch (_) {}
    await _be82Sub?.cancel();
    _be82Sub = null;
    await _centralConnSub?.cancel();
    _centralConnSub = null;
    try {
      await _centralDevice?.disconnect();
    } catch (_) {}
    _centralDevice = null;
    _be81 = null;
    _peripheralDeviceId = null;
    _mode = _InstaLinkMode.none;
    connectedName = keepSaved ? selectedDevice?.name : null;
    _sessionRecording = false;
    status = const Insta360CameraStatus();
    _setState(Insta360ConnectionState.disconnected);
  }

  void _setState(Insta360ConnectionState next) {
    _state = next;
    notifyListeners();
  }

  /// Free the radio for GoPro (stop advertising / drop peripheral or central).
  Future<void> yieldRadio() async {
    await stopScan();
    await _teardown(keepSaved: true);
  }

  @override
  void dispose() {
    unawaited(stopScan());
    unawaited(_teardown(keepSaved: true));
    super.dispose();
  }
}
