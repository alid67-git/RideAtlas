import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'gopro/client.dart';
import 'gopro/models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const GoProRemoteApp());
}

class GoProRemoteApp extends StatelessWidget {
  const GoProRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoPro Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE85D04),
          brightness: Brightness.dark,
          surface: const Color(0xFF121418),
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0D10),
      ),
      home: const RemoteHomePage(),
    );
  }
}

class RemoteHomePage extends StatefulWidget {
  const RemoteHomePage({super.key});

  @override
  State<RemoteHomePage> createState() => _RemoteHomePageState();
}

class _RemoteHomePageState extends State<RemoteHomePage> {
  late final GoProBleClient _client;
  bool _busy = false;
  String? _banner;

  @override
  void initState() {
    super.initState();
    _client = GoProBleClient()..addListener(_onClient);
  }

  void _onClient() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _client
      ..removeListener(_onClient)
      ..dispose();
    super.dispose();
  }

  Future<bool> _ensurePermissions() async {
    final asked = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];
    final statuses = await asked.request();
    final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final connectOk = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    // Location still required on many Android builds for BLE scan results.
    final locOk = statuses[Permission.locationWhenInUse]?.isGranted ?? false;
    if (!scanOk || !connectOk) {
      _banner = 'Bluetooth izinleri gerekli (Scan + Connect).';
      setState(() {});
      return false;
    }
    if (!locOk) {
      _banner = 'Konum izni BLE taraması için gerekli (Android kısıtı).';
      setState(() {});
      return false;
    }
    return true;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _banner = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _banner = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    if (!await _ensurePermissions()) return;
    await _run(() => _client.startScan());
  }

  Future<void> _connect(GoProDeviceInfo info) async {
    if (!await _ensurePermissions()) return;
    await _run(() async {
      await _client.connect(info);
      _banner = 'Bağlandı: ${info.name}';
    });
  }

  String get _stateLabel {
    switch (_client.state) {
      case GoProConnectionState.disconnected:
        return 'Bağlı değil';
      case GoProConnectionState.scanning:
        return 'Taranıyor…';
      case GoProConnectionState.connecting:
        return 'Bağlanıyor…';
      case GoProConnectionState.connected:
        return 'Bağlı';
      case GoProConnectionState.error:
        return 'Hata';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = _client.status;
    final connected = _client.isConnected;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GoPro Remote',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'HERO10–13 Black · Open GoPro BLE · Android',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.65),
                        ),
                  ),
                ],
              ),
            ),
            if (_banner != null || _client.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: cs.errorContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _banner ?? _client.error!,
                      style: TextStyle(color: cs.onErrorContainer),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _StatusCard(
                stateLabel: _stateLabel,
                deviceName: _client.connectedDevice?.name,
                status: st,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _busy ? null : _scan,
                      icon: const Icon(Icons.bluetooth_searching),
                      label: Text(
                        _client.state == GoProConnectionState.scanning
                            ? 'Taranıyor'
                            : 'Tara',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_busy || !connected)
                          ? null
                          : () => _run(_client.disconnect),
                      icon: const Icon(Icons.link_off),
                      label: const Text('Kopar'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _RecordControls(
                enabled: connected && !_busy,
                encoding: st.encoding,
                onStart: () => _run(_client.startRecording),
                onStop: () => _run(_client.stopRecording),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: Icon(
                      st.wifiApEnabled ? Icons.wifi : Icons.wifi_off,
                      size: 18,
                    ),
                    label: Text(
                      st.wifiApEnabled ? 'Wi‑Fi AP kapat' : 'Wi‑Fi AP aç',
                    ),
                    onPressed: (!connected || _busy)
                        ? null
                        : () => _run(
                              () => _client.setWifiAp(!st.wifiApEnabled),
                            ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.refresh, size: 18),
                    label: const Text('SSID yenile'),
                    onPressed: (!connected || _busy)
                        ? null
                        : () => _run(_client.refreshWifiCredentials),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.bedtime, size: 18),
                    label: const Text('Uyku'),
                    onPressed: (!connected || _busy)
                        ? null
                        : () => _run(_client.sleepCamera),
                  ),
                ],
              ),
            ),
            if (st.wifiSsid != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  'AP: ${st.wifiSsid}'
                  '${st.wifiPassword != null ? '  ·  ${st.wifiPassword}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.7),
                        fontFamily: 'monospace',
                      ),
                ),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'Bulunan kameralar',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.75),
                    ),
              ),
            ),
            Expanded(
              child: _client.discovered.isEmpty
                  ? Center(
                      child: Text(
                        'Kamerayı aç, Bluetooth’u açık tut.\n'
                        'İlk seferde GoPro’da eşleştirme isteğini onayla.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: _client.discovered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final d = _client.discovered[i];
                        final selected =
                            _client.connectedDevice?.remoteId == d.remoteId;
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: selected
                                  ? cs.primary
                                  : cs.outline.withValues(alpha: 0.25),
                            ),
                          ),
                          leading: Icon(
                            Icons.videocam,
                            color: selected ? cs.primary : cs.onSurface,
                          ),
                          title: Text(d.name),
                          subtitle: Text(
                            '${d.modelHint}'
                            '${d.rssi != null ? ' · ${d.rssi} dBm' : ''}',
                          ),
                          trailing: selected
                              ? Icon(Icons.check_circle, color: cs.primary)
                              : const Icon(Icons.chevron_right),
                          onTap: _busy ? null : () => _connect(d),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.stateLabel,
    required this.deviceName,
    required this.status,
  });

  final String stateLabel;
  final String? deviceName;
  final GoProCameraStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final duration = status.encodingDurationSec;
    final durText = duration == null
        ? '—'
        : '${(duration ~/ 60).toString().padLeft(2, '0')}:'
            '${(duration % 60).toString().padLeft(2, '0')}';

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A1F27),
            Color.lerp(const Color(0xFF1A1F27), cs.primary, 0.12)!,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Dot(active: status.encoding, color: const Color(0xFFE5383B)),
                const SizedBox(width: 8),
                Text(
                  status.encoding ? 'KAYIT' : stateLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                if (status.batteryPercent != null)
                  Row(
                    children: [
                      const Icon(Icons.battery_std, size: 18),
                      const SizedBox(width: 4),
                      Text('${status.batteryPercent}%'),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              deviceName ?? 'Kamera seçilmedi',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Metric(label: 'Süre', value: durText),
                const SizedBox(width: 24),
                _Metric(
                  label: 'Wi‑Fi AP',
                  value: status.wifiApEnabled ? 'Açık' : 'Kapalı',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? color : color.withValues(alpha: 0.25),
        boxShadow: active
            ? [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 8)]
            : null,
      ),
    );
  }
}

class _RecordControls extends StatelessWidget {
  const _RecordControls({
    required this.enabled,
    required this.encoding,
    required this.onStart,
    required this.onStop,
  });

  final bool enabled;
  final bool encoding;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE5383B),
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    const Color(0xFFE5383B).withValues(alpha: 0.25),
              ),
              onPressed: enabled && !encoding ? onStart : null,
              child: const Text('KAYDI BAŞLAT'),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 56,
            child: FilledButton.tonal(
              onPressed: enabled && encoding ? onStop : null,
              child: const Text('DURDUR'),
            ),
          ),
        ),
      ],
    );
  }
}
