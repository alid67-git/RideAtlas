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
import 'insta360/models.dart'
    show Insta360CancelledException, Insta360ConnectionState;
import 'services/app_update_controller.dart';
import 'services/update_checker.dart';
import 'widgets/app_update_ui.dart';
import 'widgets/devices_page.dart';
import 'widgets/insta_devices_page.dart';

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
  bool _instaBusy = false;
  String? _goproBanner;
  String? _instaBanner;

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
    if (!mounted) return;
    // Drop banners that contradict live link state.
    final b = _instaBanner?.toLowerCase();
    if (b != null) {
      if (_insta.isConnected &&
          (b.contains('kapandı') || b.contains('bağlantı yok'))) {
        _instaBanner = null;
      } else if (!_insta.isConnected &&
          !_instaBusy &&
          b.contains('bağlandı')) {
        _instaBanner = null;
      }
    }
    setState(() {});
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
    await _insta.ensurePrefsLoaded();
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

  Future<bool> _ensurePermissions({bool forInsta = false}) async {
    final asked = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ];
    final statuses = await asked.request();
    final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final connectOk = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    final advertiseOk =
        statuses[Permission.bluetoothAdvertise]?.isGranted ?? false;
    final locOk = statuses[Permission.locationWhenInUse]?.isGranted ?? false;
    void setBanner(String msg) {
      if (forInsta) {
        _instaBanner = msg;
      } else {
        _goproBanner = msg;
      }
      setState(() {});
    }

    if (!scanOk || !connectOk) {
      setBanner('Bluetooth izinleri gerekli (Scan + Connect).');
      return false;
    }
    // Advertise is only needed for GPS-Remote wake (peripheral). Central be80
    // control works without it — don't block Bağlan / KAYIT when it's missing.
    if (forInsta && !advertiseOk) {
      // Soft warning only; central path still proceeds.
    }
    if (!locOk) {
      setBanner('Konum izni BLE taraması için gerekli (Android kısıtı).');
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
    // Insta360 GPS-remote peripheral fights GoPro central on many phones.
    try {
      await _insta.yieldRadio();
    } catch (_) {}
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
      setState(() => _goproBanner = _cleanUserMessage(friendly ?? e.toString()));
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

  Future<void> _runInsta(Future<void> Function() action) async {
    if (_instaBusy) return;
    setState(() {
      _instaBusy = true;
      _instaBanner = null;
    });
    // Free GoPro GATT so Insta360 can advertise / host the remote.
    try {
      await _gopro.yieldRadio();
    } catch (_) {}
    _insta.beginOperation();
    try {
      await action();
    } on Insta360CancelledException {
      if (mounted) setState(() => _instaBanner = 'İptal edildi');
    } catch (e) {
      if (e.toString().contains('İptal edildi')) {
        if (mounted) setState(() => _instaBanner = 'İptal edildi');
        return;
      }
      final friendly = _insta.error;
      setState(() => _instaBanner = _cleanUserMessage(friendly ?? e.toString()));
    } finally {
      if (mounted) setState(() => _instaBusy = false);
    }
  }

  Future<void> _cancelInsta() async {
    if (!_instaBusy) return;
    setState(() => _instaBanner = 'İptal ediliyor…');
    await _insta.cancelOperation();
  }

  Future<void> _toggleInstaConnectSleep() async {
    if (!await _ensurePermissions(forInsta: true)) return;
    final closing = _insta.isConnected || _insta.isSessionRecording;
    await _runInsta(() async {
      setState(() {
        _instaBanner =
            closing ? 'Kapatılıyor…' : 'Bağlanıyor (kamera açık olmalı)…';
      });
      await _insta.toggleConnectSleep();
      if (!mounted) return;
      // Always reflect live client state (avoid stale “kapandı” while Bağlı).
      setState(() {
        if (_insta.isConnected) {
          _instaBanner = 'Bağlandı: ${_insta.preferredName ?? 'Insta360'}';
        } else if (closing) {
          _instaBanner = 'Kamera kapandı · bağlantı yok';
        } else {
          _instaBanner = null;
        }
      });
    });
  }

  Future<void> _openGoProDevices() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DevicesPage(client: _gopro),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openInstaDevices() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InstaDevicesPage(client: _insta),
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

  String get _instaStateLabel {
    if (_insta.isConnected) return 'Bağlı';
    switch (_insta.state) {
      case Insta360ConnectionState.disconnected:
        return 'Bağlı değil';
      case Insta360ConnectionState.scanning:
        return 'Taranıyor…';
      case Insta360ConnectionState.advertising:
        return 'Bekleniyor…';
      case Insta360ConnectionState.connecting:
        return 'Bağlanıyor…';
      case Insta360ConnectionState.connected:
        // State alone is not enough — need live GATT/peripheral session.
        return 'Bağlı değil';
      case Insta360ConnectionState.error:
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
                  if (_goproBusy || _instaBusy)
                    IconButton(
                      tooltip: 'İptal',
                      onPressed: () {
                        if (_goproBusy) _cancelGoPro();
                        if (_instaBusy) _cancelInsta();
                      },
                      icon: const Icon(Icons.close),
                    ),
                  IconButton(
                    tooltip: 'Güncelleme kontrol et',
                    onPressed: (_goproBusy || _instaBusy)
                        ? null
                        : _manualUpdateCheck,
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
                      subtitle: 'X4+ GPS Remote',
                      accent: const Color(0xFF4CC9F0),
                      child: _Insta360Section(
                        client: _insta,
                        busy: _instaBusy,
                        banner: _instaBanner,
                        stateLabel: _instaStateLabel,
                        onCancel: _cancelInsta,
                        onOpenDevices:
                            _instaBusy ? null : _openInstaDevices,
                        onRecord: () => _runInsta(() async {
                          if (!await _ensurePermissions(forInsta: true)) {
                            return;
                          }
                          final wasRecording = _insta.isSessionRecording;
                          setState(() {
                            _instaBanner = wasRecording
                                ? 'Durduruluyor, kamera kapatılıyor…'
                                : 'Uyandırılıyor → kayıt…';
                          });
                          await _insta.toggleRecording();
                          setState(() {
                            _instaBanner = wasRecording
                                ? 'Kayıt durdu · kamera kapalı'
                                : 'Kayıt başladı';
                          });
                        }),
                        onConnectSleep: _toggleInstaConnectSleep,
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
                if (busy || banner != null || client.error != null)
                  _ToneBanner(
                    busy: busy,
                    text: _cleanUserMessage(
                      banner ?? client.error ?? 'İşlem sürüyor…',
                    ),
                    onCancel: busy ? onCancel : null,
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
                const SizedBox(height: 14),
                _ControlPad(
                  // Bağlan/Uyut — same blue as Insta360 power control.
                  accent: const Color(0xFF4CC9F0),
                  recording: client.isSessionRecording,
                  busy: busy,
                  enabled: true,
                  recordLabel:
                      client.isSessionRecording ? 'DURDUR + UYKU' : 'KAYIT',
                  onRecord: onRecord,
                  powerBusy: linking,
                  powerConnected: connected,
                  powerLabel: linking
                      ? 'Bağlanıyor…'
                      : (connected ? 'Uyut / kapat' : 'Bağlan'),
                  onPower: busy ? null : onConnectSleep,
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
    required this.busy,
    required this.banner,
    required this.stateLabel,
    required this.onCancel,
    required this.onOpenDevices,
    required this.onRecord,
    required this.onConnectSleep,
  });

  final Insta360Client client;
  final bool busy;
  final String? banner;
  final String stateLabel;
  final VoidCallback onCancel;
  final VoidCallback? onOpenDevices;
  final VoidCallback onRecord;
  final VoidCallback onConnectSleep;

  @override
  Widget build(BuildContext context) {
    final connected = client.isConnected;
    final linking = client.state == Insta360ConnectionState.scanning ||
        client.state == Insta360ConnectionState.advertising ||
        client.state == Insta360ConnectionState.connecting;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (busy || banner != null || client.error != null)
                  _ToneBanner(
                    busy: busy,
                    text: _cleanUserMessage(
                      banner ?? client.error ?? 'İşlem sürüyor…',
                    ),
                    onCancel: busy ? onCancel : null,
                  ),
                _CompactStatus(
                  stateLabel: stateLabel,
                  deviceName: client.preferredName,
                  durationSec: client.status.encodingDurationSec,
                  batteryPercent: client.status.batteryPercent,
                  sessionRecording: client.isSessionRecording,
                  accent: const Color(0xFF4CC9F0),
                  onDeviceTap: onOpenDevices,
                ),
                const SizedBox(height: 14),
                _ControlPad(
                  accent: const Color(0xFF4CC9F0),
                  recording: client.isSessionRecording,
                  busy: busy,
                  enabled: true,
                  recordLabel:
                      client.isSessionRecording ? 'DURDUR + KAPAT' : 'KAYIT',
                  onRecord: onRecord,
                  powerBusy: linking,
                  powerConnected: connected,
                  powerLabel: linking
                      ? 'Bekleniyor…'
                      : (connected ? 'Kapat' : 'Bağlan'),
                  onPower: busy ? null : onConnectSleep,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _cleanUserMessage(String raw) {
  var text = raw.trim();
  if (text.startsWith('Bad state: ')) {
    text = text.substring('Bad state: '.length);
  }
  if (text.startsWith('Exception: ')) {
    text = text.substring('Exception: '.length);
  }
  if (text.startsWith('StateError: ')) {
    text = text.substring('StateError: '.length);
  }
  return text;
}

bool _looksLikeSuccessBanner(String text) {
  final t = text.toLowerCase();
  return t.contains('başladı') ||
      t.contains('bağlandı') ||
      t.contains('durdu') ||
      t.contains('uyku') ||
      t.contains('kapandı') ||
      t.contains('kapalı') ||
      t.contains('güncelsin');
}

class _ToneBanner extends StatelessWidget {
  const _ToneBanner({
    required this.busy,
    required this.text,
    this.onCancel,
  });

  final bool busy;
  final String text;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final success = !busy && _looksLikeSuccessBanner(text);
    final Color color;
    final Color foreground;
    if (busy) {
      color = cs.secondaryContainer.withValues(alpha: 0.45);
      foreground = cs.onSecondaryContainer;
    } else if (success) {
      color = const Color(0xFF2A9D8F).withValues(alpha: 0.28);
      foreground = const Color(0xFFB8F2E6);
    } else {
      color = cs.errorContainer.withValues(alpha: 0.35);
      foreground = cs.onErrorContainer;
    }

    final trailing = onCancel == null
        ? null
        : IconButton(
            tooltip: 'İptal',
            onPressed: onCancel,
            icon: Icon(Icons.close, color: foreground, size: 20),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            trailing == null ? 10 : 2,
            4,
            trailing == null ? 10 : 2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: foreground, fontSize: 13),
                ),
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

class _ControlPad extends StatelessWidget {
  const _ControlPad({
    required this.accent,
    required this.recording,
    required this.busy,
    required this.enabled,
    required this.recordLabel,
    required this.onRecord,
    required this.powerBusy,
    required this.powerConnected,
    required this.powerLabel,
    required this.onPower,
  });

  final Color accent;
  final bool recording;
  final bool busy;
  final bool enabled;
  final String recordLabel;
  final VoidCallback onRecord;
  final bool powerBusy;
  final bool powerConnected;
  final String powerLabel;
  final VoidCallback? onPower;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ShutterButton(
              recording: recording,
              busy: busy,
              enabled: enabled,
              label: recordLabel,
              onPressed: onRecord,
            ),
            const SizedBox(width: 28),
            _PowerButton(
              accent: accent,
              busy: powerBusy,
              connected: powerConnected,
              enabled: enabled && onPower != null,
              label: powerLabel,
              onPressed: onPower,
            ),
          ],
        ),
      ],
    );
  }
}

/// Circular camera shutter: red disc to start, teal stop square while recording.
class _ShutterButton extends StatefulWidget {
  const _ShutterButton({
    required this.recording,
    required this.busy,
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final bool recording;
  final bool busy;
  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<_ShutterButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final canTap = widget.enabled && !widget.busy;
    final ring = widget.recording
        ? const Color(0xFF2A9D8F)
        : const Color(0xFFE5383B);
    final face = widget.recording
        ? const Color(0xFF1F7A6E)
        : const Color(0xFFC81D25);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: canTap ? (_) => setState(() => _pressed = true) : null,
          onTapUp: canTap
              ? (_) {
                  setState(() => _pressed = false);
                  widget.onPressed();
                }
              : null,
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.92 : 1,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: canTap ? 1 : 0.38,
              duration: const Duration(milliseconds: 160),
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF14181F),
                  border: Border.all(color: ring, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: ring.withValues(alpha: 0.28),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: widget.recording ? 34 : 62,
                  height: widget.recording ? 34 : 62,
                  decoration: BoxDecoration(
                    color: face,
                    borderRadius: BorderRadius.circular(
                      widget.recording ? 8 : 31,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.busy ? '…' : widget.label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: ring.withValues(alpha: canTap ? 1 : 0.45),
              ),
        ),
      ],
    );
  }
}

/// Round power / connect control beside the shutter.
class _PowerButton extends StatefulWidget {
  const _PowerButton({
    required this.accent,
    required this.busy,
    required this.connected,
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final Color accent;
  final bool busy;
  final bool connected;
  final bool enabled;
  final String label;
  final VoidCallback? onPressed;

  @override
  State<_PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<_PowerButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final canTap = widget.enabled && widget.onPressed != null && !widget.busy;
    final icon = widget.busy
        ? Icons.hourglass_top
        : (widget.connected
            ? Icons.power_settings_new
            : Icons.bluetooth_searching);
    final fill = widget.connected
        ? widget.accent.withValues(alpha: 0.22)
        : const Color(0xFF1A1F27);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: canTap ? (_) => setState(() => _pressed = true) : null,
          onTapUp: canTap
              ? (_) {
                  setState(() => _pressed = false);
                  widget.onPressed?.call();
                }
              : null,
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.92 : 1,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: canTap ? 1 : 0.38,
              duration: const Duration(milliseconds: 160),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill,
                  border: Border.all(
                    color: widget.accent.withValues(alpha: 0.85),
                    width: 2.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: widget.accent, size: 28),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: widget.accent.withValues(alpha: canTap ? 0.95 : 0.4),
              ),
        ),
      ],
    );
  }
}
