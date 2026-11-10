import 'dart:async';
import 'dart:convert';

import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    hide CharacteristicProperties;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'protocol.dart';
import 'uuids.dart';

/// Insta360 remote via GPS-Remote emulation (phone = BLE peripheral).
///
/// The camera is the BLE central: it wakes on our ORBIT advertisement, connects
/// to `ce80`, subscribes to `ce82`, and accepts shutter / power button frames.
class Insta360Client extends ChangeNotifier {
  Insta360ConnectionState _state = Insta360ConnectionState.disconnected;
  Insta360ConnectionState get state => _state;

  String? _error;
  String? get error => _error;

  String? connectedName;
  String? _connectedDeviceId;
  Insta360CameraStatus status = const Insta360CameraStatus();

  bool _sessionRecording = false;
  bool get isSessionRecording => _sessionRecording || status.encoding;

  bool get isConnected =>
      _state == Insta360ConnectionState.connected && _connectedDeviceId != null;

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

  bool _prefsLoaded = false;
  bool _gattReady = false;
  bool _cancelRequested = false;
  bool get isCancelRequested => _cancelRequested;

  int _buttonSeq = 0;
  Completer<void>? _serviceAddCompleter;
  Completer<void>? _connectedCompleter;
  StreamSubscription<List<ScanResult>>? _scanSub;

  void beginOperation() {
    _cancelRequested = false;
  }

  Future<void> cancelOperation() async {
    _cancelRequested = true;
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
    if (_selectedSerial != null &&
        !_savedDevices.any((d) => d.serial == _selectedSerial)) {
      _selectedSerial = _savedDevices.isEmpty ? null : _savedDevices.first.serial;
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

  Future<void> _ensureGattServer() async {
    if (_gattReady) return;

    final supported = await BlePeripheral.isSupported();
    if (!supported) {
      throw StateError('Bu telefonda BLE peripheral (kumanda) desteklenmiyor.');
    }

    await BlePeripheral.initialize();

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
        _connectedDeviceId = deviceId;
        connectedName = selectedDevice?.name ?? 'Insta360';
        _buttonSeq = 0;
        _setState(Insta360ConnectionState.connected);
        final waiting = _connectedCompleter;
        if (waiting != null && !waiting.isCompleted) {
          waiting.complete();
        }
      } else if (_connectedDeviceId == deviceId || _connectedDeviceId == null) {
        _connectedDeviceId = null;
        if (_sessionRecording) {
          _sessionRecording = false;
        }
        if (_state != Insta360ConnectionState.disconnected) {
          _setState(Insta360ConnectionState.disconnected);
        }
      }
    });

    BlePeripheral.setWriteRequestCallback((deviceId, characteristicId, offset, value) {
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

    BlePeripheral.setReadRequestCallback((deviceId, characteristicId, offset, value) {
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

    // Wake ADV is a full 31-byte legacy packet — omit service UUIDs so the
    // ORBIT manufacturer payload fits. GATT services stay registered for when
    // the camera connects.
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
      // Some stacks reject empty service lists or long local names with manuf.
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
    await BlePeripheral.updateCharacteristic(
      characteristicId: InstaUuids.charCe82,
      value: frame,
      deviceId: _connectedDeviceId,
    );
  }

  int _nextSeq() {
    final sn = _buttonSeq;
    _buttonSeq = (_buttonSeq + 2) & 0xff;
    return sn;
  }

  Future<void> _sendShutter() async {
    await _notifyButton(shutterClickFrame(_nextSeq()));
  }

  /// Power-off is a sustained hold (~2s of held frames), not a single click.
  Future<void> _sendPowerOffHold({
    Duration duration = const Duration(milliseconds: 2000),
  }) async {
    final end = DateTime.now().add(duration);
    while (DateTime.now().isBefore(end)) {
      _ensureNotCancelled();
      await _notifyButton(powerHoldFrame(_nextSeq()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> toggleConnectSleep() async {
    await ensurePrefsLoaded();
    _error = null;

    if (isConnected || _sessionRecording) {
      _setState(Insta360ConnectionState.connecting);
      try {
        if (isConnected) {
          await _sendPowerOffHold();
        }
      } catch (e) {
        _error = e.toString();
      }
      _sessionRecording = false;
      status = const Insta360CameraStatus();
      await _teardown(keepSaved: true);
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
    await _ensureGattServer();
    _ensureNotCancelled();

    _setState(Insta360ConnectionState.advertising);
    connectedName = selected.name;
    _connectedCompleter = Completer<void>();

    // Wake beacon for sleeping cameras, then also stay discoverable.
    await _startWakeAdvertising(selected.serial);

    // Brief second pass as classic remote advertisement helps first-time pair.
    unawaited(Future<void>.delayed(const Duration(seconds: 3), () async {
      if (_cancelRequested || isConnected) return;
      try {
        await _startDiscoverableAdvertising();
        // Re-assert wake manuf shortly after — sleeping cameras need ORBIT.
        await Future<void>.delayed(const Duration(seconds: 2));
        if (_cancelRequested || isConnected) return;
        await _startWakeAdvertising(selected.serial);
      } catch (_) {}
    }));

    try {
      await _connectedCompleter!.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          throw StateError(
            'Kamera bağlanmadı. Kamerayı açıp GPS Remote eşleştirmesini kontrol et, '
            'veya seri numarasını doğrula (${selected.serial}).',
          );
        },
      );
      _ensureNotCancelled();
      // Screen-on nudge after connect.
      try {
        await _notifyButton(powerClickFrame(_nextSeq()));
      } catch (_) {}
    } catch (e) {
      await _teardown(keepSaved: true);
      rethrow;
    }
  }

  Future<void> toggleRecording() async {
    await ensurePrefsLoaded();
    _error = null;

    if (!isConnected) {
      await toggleConnectSleep();
      // Small settle after connect before shutter.
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    _ensureNotCancelled();
    if (!isConnected) {
      throw StateError('Insta360 bağlı değil');
    }

    final wasRecording = isSessionRecording;
    await _sendShutter();
    _sessionRecording = !wasRecording;
    status = status.copyWith(
      encoding: _sessionRecording,
      encodingDurationSec: _sessionRecording ? 0 : status.encodingDurationSec,
    );
    notifyListeners();

    if (wasRecording) {
      // Match GoPro UX: stop then sleep/power-off.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _ensureNotCancelled();
      try {
        await _sendPowerOffHold();
      } catch (_) {}
      await _teardown(keepSaved: true);
    }
  }

  Future<void> _teardown({required bool keepSaved}) async {
    try {
      await BlePeripheral.stopAdvertising();
    } catch (_) {}
    _connectedDeviceId = null;
    connectedName = keepSaved ? selectedDevice?.name : null;
    _sessionRecording = false;
    status = const Insta360CameraStatus();
    _setState(Insta360ConnectionState.disconnected);
  }

  void _setState(Insta360ConnectionState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stopScan());
    unawaited(_teardown(keepSaved: true));
    super.dispose();
  }
}
