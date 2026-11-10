import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'build_info.dart';
import 'gopro/client.dart';
import 'gopro/models.dart'
    show GoProCancelledException, GoProConnectionState;
import 'insta360/client.dart';
import 'services/app_update_controller.dart';
import 'services/update_checker.dart';
import 'widgets/app_update_ui.dart';
import 'widgets/devices_page.dart';

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
        title: 'Camera Remote',
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
  late final GoProBleClient _gopro;
  late final Insta360Client _insta;
  bool _goproBusy = false;
  String? _goproBanner;

  @override
  void initState() {
    super.initState();
    _gopro = GoProBleClient()..addListener(_onChange);
    _insta = Insta360Client()..addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _bootstrap();
    });
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _gopro
      ..removeListener(_onChange)
      ..dispose();
    _insta
      ..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    unawaited(_ensurePermissions());
    await _gopro.ensurePrefsLoaded();
    if (!mounted) return;

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
      _goproBanner = 'Bluetooth izinleri gerekli (Scan + Connect).';
      setState(() {});
      return false;
    }
    if (!locOk) {
      _goproBanner = 'Konum izni BLE taraması için gerekli (Android kısıtı).';
      setState(() {});
      return false;
    }
    return true;
  }

  Future<void> _runGoPro(Future<void> Function() action) async {
    if (_goproBusy) return;
    setState(() {
      _goproBusy = true;
      _goproBanner = null;
    });
    _gopro.beginOperation();
    try {
      await action();
    } on GoProCancelledException {
      if (mounted) setState(() => _goproBanner = 'İptal edildi');
    } catch (e) {
      if (e.toString().contains('İptal edildi')) {
        if (mounted) setState(() => _goproBanner = 'İptal edildi');
        return;
      }
      final friendly = _gopro.error;
      final raw = e.toString();
      final cleaned = raw.startsWith('Bad state: ')
          ? raw.substring('Bad state: '.length)
          : raw;
      setState(() => _goproBanner = friendly ?? cleaned);
    } finally {
      if (mounted) setState(() => _goproBusy = false);
    }
  }

  Future<void> _cancelGoPro() async {
    if (!_goproBusy) return;
    setState(() => _goproBanner = 'İptal ediliyor…');
    await _gopro.cancelOperation();
  }

  Future<void> _toggleGoProConnectSleep() async {
    if (!await _ensurePermissions()) return;
    final closing = _gopro.isConnected || _gopro.isSessionRecording;
    await _runGoPro(() async {
      setState(() {
        _goproBanner = closing ? 'Uyutuluyor / kapatılıyor…' : 'Uyandırılıyor…';
      });
      await _gopro.toggleConnectSleep();
      if (!mounted) return;
      setState(() {
        _goproBanner = closing
            ? 'Kamera uyku · bağlantı kapandı'
            : (_gopro.connectedDevice == null
                ? null
                : 'Bağlandı: ${_gopro.connectedDevice!.name}');
      });
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

  Future<void> _openGoProDevices() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DevicesPage(client: _gopro),
      ),
    );
    if (mounted) setState(() {});
  }

  String get _goproStateLabel {
    switch (_gopro.state) {
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Camera Remote',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          kAppBuildLabel,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.55),
                                  ),
                        ),
                      ],
                    ),
                  ),
                  if (_goproBusy)
                    IconButton(
                      tooltip: 'İptal',
                      onPressed: _cancelGoPro,
                      icon: const Icon(Icons.close),
                    ),
                  IconButton(
                    tooltip: 'Güncelleme kontrol et',
                    onPressed: _goproBusy ? null : _manualUpdateCheck,
                    icon: const Icon(Icons.system_update_alt),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: AppUpdateBanner(),
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: _BrandPanel(
                      title: 'GoPro',
                      subtitle: 'HERO10–13',
                      accent: const Color(0xFFE85D04),
                      child: _GoProSection(
                        client: _gopro,
                        busy: _goproBusy,
                        banner: _goproBanner,
                        stateLabel: _goproStateLabel,
                        onCancel: _cancelGoPro,
                        onOpenDevices: _goproBusy ? null : _openGoProDevices,
                        onRecord: () => _runGoPro(() async {
                          if (!await _ensurePermissions()) return;
                          final wasRecording = _gopro.isSessionRecording;
                          setState(() {
                            _goproBanner = wasRecording
                                ? 'Durduruluyor, kamera uykuya alınıyor…'
                                : 'Uyandırılıyor → kayıt…';
                          });
                          await _gopro.toggleRecording();
                          setState(() {
                            _goproBanner = wasRecording
                                ? 'Kayıt durdu · kamera uyku'
                                : 'Kayıt başladı';
                          });
                        }),
                        onConnectSleep: _toggleGoProConnectSleep,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(
                      height: 1,
                      color: cs.outline.withValues(alpha: 0.35),
                    ),
                  ),
                  Expanded(
                    child: _BrandPanel(
                      title: 'Insta360',
                      subtitle: 'X4+',
                      accent: const Color(0xFF4CC9F0),
                      child: _Insta360Section(
                        client: _insta,
                        onTapSoon: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Insta360 X4+ kumandası yakında eklenecek.',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(width: 8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _GoProSection extends StatelessWidget {
  const _GoProSection({
    required this.client,
    required this.busy,
    required this.banner,
    required this.stateLabel,
    required this.onCancel,
    required this.onOpenDevices,
    required this.onRecord,
    required this.onConnectSleep,
  });

  final GoProBleClient client;
  final bool busy;
  final String? banner;
  final String stateLabel;
  final VoidCallback onCancel;
  final VoidCallback? onOpenDevices;
  final VoidCallback onRecord;
  final VoidCallback onConnectSleep;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final connected = client.isConnected;
    final linking = client.state == GoProConnectionState.scanning ||
        client.state == GoProConnectionState.connecting;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (busy)
                  _InlineBanner(
                    color: cs.secondaryContainer.withValues(alpha: 0.45),
                    foreground: cs.onSecondaryContainer,
                    text: banner ?? 'İşlem sürüyor…',
                    trailing: IconButton(
                      tooltip: 'İptal',
                      onPressed: onCancel,
                      icon: Icon(
                        Icons.close,
                        color: cs.onSecondaryContainer,
                        size: 20,
                      ),
                    ),
                  )
                else if (banner != null || client.error != null)
                  _InlineBanner(
                    color: cs.errorContainer.withValues(alpha: 0.35),
                    foreground: cs.onErrorContainer,
                    text: banner ?? client.error!,
                  ),
                _CompactStatus(
                  stateLabel: stateLabel,
                  deviceName:
                      client.connectedDevice?.name ?? client.preferredName,
                  durationSec: client.status.encodingDurationSec,
                  batteryPercent: client.status.batteryPercent,
                  sessionRecording: client.isSessionRecording,
                  accent: const Color(0xFFE85D04),
                  onDeviceTap: onOpenDevices,
                ),
                const SizedBox(height: 8),
                _RecordToggleButton(
                  busy: busy,
                  encoding: client.isSessionRecording,
                  compact: true,
                  onPressed: onRecord,
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: busy ? null : onConnectSleep,
                  icon: Icon(
                    linking
                        ? Icons.hourglass_top
                        : (connected
                            ? Icons.power_settings_new
                            : Icons.bluetooth_searching),
                    size: 18,
                  ),
                  label: Text(
                    linking
                        ? 'Bağlanıyor…'
                        : (connected
                            ? 'Uyut / kapat'
                            : 'Sadece bağlan (uyandır)'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Insta360Section extends StatelessWidget {
  const _Insta360Section({
    required this.client,
    required this.onTapSoon,
  });

  final Insta360Client client;
  final VoidCallback onTapSoon;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CompactStatus(
                  stateLabel: 'Yakında',
                  deviceName: 'Insta360 seçilmedi',
                  durationSec: null,
                  batteryPercent: null,
                  sessionRecording: false,
                  accent: const Color(0xFF4CC9F0),
                  onDeviceTap: onTapSoon,
                ),
                const SizedBox(height: 8),
                _RecordToggleButton(
                  busy: false,
                  encoding: false,
                  compact: true,
                  enabled: false,
                  labelOverride: 'KAYIT (yakında)',
                  onPressed: onTapSoon,
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: onTapSoon,
                  icon: const Icon(Icons.bluetooth_searching, size: 18),
                  label: const Text('Sadece bağlan (yakında)'),
                ),
                const SizedBox(height: 12),
                Text(
                  'X4+ BLE/Wi‑Fi kumandası sonraki sürümde.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.45),
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InlineBanner extends StatelessWidget {
  const _InlineBanner({
    required this.color,
    required this.foreground,
    required this.text,
    this.trailing,
  });

  final Color color;
  final Color foreground;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, trailing == null ? 10 : 2, 4, trailing == null ? 10 : 2),
          child: Row(
            children: [
              Expanded(
                child: Text(text, style: TextStyle(color: foreground, fontSize: 13)),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactStatus extends StatelessWidget {
  const _CompactStatus({
    required this.stateLabel,
    required this.deviceName,
    required this.durationSec,
    required this.batteryPercent,
    required this.sessionRecording,
    required this.accent,
    this.onDeviceTap,
  });

  final String stateLabel;
  final String? deviceName;
  final int? durationSec;
  final int? batteryPercent;
  final bool sessionRecording;
  final Color accent;
  final VoidCallback? onDeviceTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final durText = durationSec == null
        ? '—'
        : '${(durationSec! ~/ 60).toString().padLeft(2, '0')}:'
            '${(durationSec! % 60).toString().padLeft(2, '0')}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F27),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                Text(
                  'Süre $durText',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                ),
                if (batteryPercent != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    '${batteryPercent!}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: onDeviceTap,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Icon(Icons.videocam_outlined, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      deviceName ?? 'Kamera seçilmedi',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? color : color.withValues(alpha: 0.25),
      ),
    );
  }
}

class _RecordToggleButton extends StatelessWidget {
  const _RecordToggleButton({
    required this.busy,
    required this.encoding,
    required this.onPressed,
    this.compact = false,
    this.enabled = true,
    this.labelOverride,
  });

  final bool busy;
  final bool encoding;
  final VoidCallback onPressed;
  final bool compact;
  final bool enabled;
  final String? labelOverride;

  @override
  Widget build(BuildContext context) {
    final bg = encoding ? const Color(0xFF2A9D8F) : const Color(0xFFE5383B);
    return SizedBox(
      height: compact ? 52 : 72,
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          disabledBackgroundColor: bg.withValues(alpha: 0.28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: (!enabled || busy) ? null : onPressed,
        child: Text(
          labelOverride ?? (encoding ? 'KAYDI DURDUR + UYKU' : 'KAYIT'),
          style: TextStyle(
            fontSize: compact ? 16 : 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
