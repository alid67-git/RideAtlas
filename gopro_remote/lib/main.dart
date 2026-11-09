import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'build_info.dart';
import 'gopro/client.dart';
import 'gopro/models.dart' show GoProCameraStatus, GoProConnectionState;
import 'services/app_update_controller.dart';
import 'services/update_checker.dart';
import 'widgets/app_update_ui.dart';

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
    return ChangeNotifierProvider(
      create: (_) => AppUpdateController(),
      child: MaterialApp(
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
      ),
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
    // Do NOT auto-connect on launch — that held _busy and delayed KAYIT.
    // Record button owns wake→shutter. Only probe updates + ask permissions.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _bootstrap();
    });
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

  Future<void> _bootstrap() async {
    if (!mounted) return;
    // Warm permissions so the first KAYIT isn't blocked on dialogs.
    unawaited(_ensurePermissions());

    final updates = context.read<AppUpdateController>();
    updates.startDailyNoonChecks(
      onUpdateFound: () async {
        if (!mounted) return;
        await installAppUpdate(context);
      },
    );

    if (AppUpdateController.isSupported) {
      await updates.check();
      if (!mounted) return;
      if (updates.available != null) {
        await installAppUpdate(context);
      }
    }
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
      final friendly = _client.error;
      final raw = e.toString();
      final cleaned = raw.startsWith('Bad state: ')
          ? raw.substring('Bad state: '.length)
          : raw;
      setState(() => _banner = friendly ?? cleaned);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    if (!await _ensurePermissions()) return;
    await _run(() async {
      setState(() => _banner = 'Bağlanıyor…');
      await _client.autoConnect(
        scanTimeout: const Duration(seconds: 5),
        connectRetries: 3,
        fastRecord: true,
      );
      final name = _client.connectedDevice?.name;
      setState(() => _banner = name == null ? null : 'Bağlandı: $name');
    });
  }

  Future<void> _manualUpdateCheck() async {
    final updates = context.read<AppUpdateController>();
    final status = await updates.checkNow();
    if (!mounted) return;
    switch (status) {
      case AndroidUpdateProbeStatus.upToDate:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Güncelsin ($kAppBuildLabel)')),
        );
      case AndroidUpdateProbeStatus.updateAvailable:
        await installAppUpdate(context);
      case AndroidUpdateProbeStatus.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Güncelleme kontrolü başarısız.')),
        );
    }
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GoPro Remote',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'HERO10–13 · $kAppBuildLabel',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.65),
                                  ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Güncelleme kontrol et',
                    onPressed: _manualUpdateCheck,
                    icon: const Icon(Icons.system_update_alt),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AppUpdateBanner(),
            ),
            if (_banner != null || _client.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                sessionRecording: _client.isSessionRecording,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _RecordToggleButton(
                busy: _busy,
                encoding: _client.isSessionRecording,
                onPressed: () => _run(() async {
                  if (!await _ensurePermissions()) return;
                  final wasRecording = _client.isSessionRecording;
                  setState(() {
                    _banner = wasRecording
                        ? 'Durduruluyor, kamera uykuya alınıyor…'
                        : 'Tarama → bağlan → kayıt…';
                  });
                  await _client.toggleRecording();
                  setState(() {
                    _banner = wasRecording
                        ? 'Kayıt durdu · kamera uyku'
                        : 'Kayıt başladı';
                  });
                }),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _client.isSessionRecording
                    ? 'Tekrar basınca kayıt durur ve kamera uykuya geçer.'
                    : 'KAYIT: bağlan → eşleştir → uyan → shutter. Hata olursa tekrar bas.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: TextButton.icon(
                onPressed: _busy ? null : _scan,
                icon: Icon(
                  _client.state == GoProConnectionState.scanning ||
                          _client.state == GoProConnectionState.connecting
                      ? Icons.hourglass_top
                      : Icons.bluetooth_searching,
                ),
                label: Text(
                  connected
                      ? 'Yeniden bağlan'
                      : (_client.state == GoProConnectionState.scanning ||
                              _client.state == GoProConnectionState.connecting
                          ? 'Bağlanıyor…'
                          : 'Sadece bağlan (kayıtsız)'),
                ),
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
    required this.sessionRecording,
  });

  final String stateLabel;
  final String? deviceName;
  final GoProCameraStatus status;
  final bool sessionRecording;

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
                _Dot(
                  active: sessionRecording,
                  color: const Color(0xFFE5383B),
                ),
                const SizedBox(width: 8),
                Text(
                  sessionRecording ? 'KAYIT' : stateLabel,
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
            _Metric(label: 'Süre', value: durText),
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

class _RecordToggleButton extends StatelessWidget {
  const _RecordToggleButton({
    required this.busy,
    required this.encoding,
    required this.onPressed,
  });

  final bool busy;
  final bool encoding;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bg = encoding ? const Color(0xFF2A9D8F) : const Color(0xFFE5383B);
    return SizedBox(
      height: 72,
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          disabledBackgroundColor: bg.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: busy ? null : onPressed,
        child: Text(
          encoding ? 'KAYDI DURDUR + UYKU' : 'KAYIT',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
