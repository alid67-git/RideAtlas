import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'l10n/gen/app_localizations.dart';
import 'repositories/daily_drive_backup_controller.dart';
import 'repositories/live_stats_layout_controller.dart';
import 'repositories/locale_controller.dart';
import 'repositories/photo_repository.dart';
import 'repositories/route_repository.dart';
import 'repositories/satellite_visibility_controller.dart';
import 'repositories/stat_icon_settings_controller.dart';
import 'repositories/vehicle_icon_controller.dart';
import 'screens/home_map_screen.dart';
import 'services/app_update_controller.dart';
import 'services/car_bridge.dart';
import 'services/gps_recorder.dart';
import 'navigation/root_navigator.dart';
import 'widgets/app_update_ui.dart';
import 'widgets/incoming_track_gate.dart';
import 'widgets/system_nav_bar_lift.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const RideAtlasApp());
}

class RideAtlasApp extends StatelessWidget {
  const RideAtlasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RouteRepository()..load()),
        ChangeNotifierProvider(create: (_) => PhotoRepository()..load()),
        ChangeNotifierProvider(create: (_) => LocaleController()..load()),
        ChangeNotifierProvider(create: (_) => VehicleIconController()..load()),
        ChangeNotifierProvider(
          create: (_) => SatelliteVisibilityController()..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => StatIconSettingsController()..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => LiveStatsLayoutController()..load(),
        ),
        // Lives above the Navigator so an active recording survives
        // navigating away from RecordScreen - only an explicit "discard"
        // or "finish" call ever stops it.
        ChangeNotifierProvider(create: (_) => GpsRecorder()),
        // Shared so home + recording/info screens all see the same update.
        ChangeNotifierProvider(create: (_) => AppUpdateController()),
        // Multi-day recording → one GPX per local day into a Drive/SAF folder.
        ChangeNotifierProvider(
          create: (_) => DailyDriveBackupController()..load(),
        ),
      ],
      child: _CarBridgeGate(
        child: IncomingTrackGate(
          child: Consumer<LocaleController>(
            builder: (context, localeController, _) {
              return MaterialApp(
              title: 'RideAtlas',
              debugShowCheckedModeBanner: false,
              navigatorKey: rootNavigatorKey,
              locale: localeController.locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              // Turkish is the default when following the device's language and
              // it doesn't match tr/en/de (the algorithm's own fallback would
              // otherwise be "de", just from alphabetical list order).
              localeResolutionCallback: (deviceLocale, supported) {
                if (deviceLocale != null &&
                    supported.any(
                      (l) => l.languageCode == deviceLocale.languageCode,
                    )) {
                  return Locale(deviceLocale.languageCode);
                }
                return const Locale('tr');
              },
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF1565C0),
                ),
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF1565C0),
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
              ),
              // Arms the daily-noon update probe with a navigator context
              // so a long-lived session (recording left open overnight) can
              // still silently install when GitHub gets a newer APK. Also
              // watches the live recorder for completed local days to back up.
              builder: (context, child) => _DailyNoonUpdateHost(
                child: _DailyDriveBackupHost(
                  child: SystemNavBarLift(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
              home: const HomeMapScreen(),
            );
          },
        ),
        ),
      ),
    );
  }
}

/// Starts [AppUpdateController.startDailyNoonChecks] once, with a callback
/// that runs the same silent install path as the home-screen launch check.
class _DailyNoonUpdateHost extends StatefulWidget {
  const _DailyNoonUpdateHost({required this.child});

  final Widget child;

  @override
  State<_DailyNoonUpdateHost> createState() => _DailyNoonUpdateHostState();
}

class _DailyNoonUpdateHostState extends State<_DailyNoonUpdateHost> {
  var _armed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_armed) return;
    _armed = true;
    context.read<AppUpdateController>().startDailyNoonChecks(
      onUpdateFound: () async {
        if (!mounted) return;
        await installAppUpdate(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// While a multi-day recording runs, uploads each **completed** local day
/// (not the full cumulative track) into the user-picked Drive/SAF folder.
///
/// Catch-up also runs when:
/// - backup settings finish loading / become configured (folder pick)
/// - the app returns to foreground (paused overnight with no new GPS ticks)
/// so missing days are not left waiting for the next motion event.
class _DailyDriveBackupHost extends StatefulWidget {
  const _DailyDriveBackupHost({required this.child});

  final Widget child;

  @override
  State<_DailyDriveBackupHost> createState() => _DailyDriveBackupHostState();
}

class _DailyDriveBackupHostState extends State<_DailyDriveBackupHost>
    with WidgetsBindingObserver {
  GpsRecorder? _recorder;
  DailyDriveBackupController? _backup;
  var _listening = false;
  /// After [DailyDriveBackupController.load] finishes; avoids treating
  /// every busy/error [notifyListeners] as a reason to re-sync.
  var _backupReady = false;
  var _backupWasConfigured = false;
  Timer? _debounce;
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final recorder = context.read<GpsRecorder>();
    final backup = context.read<DailyDriveBackupController>();
    if (_recorder == recorder && _backup == backup && _listening) return;

    _recorder?.removeListener(_onRecorder);
    _backup?.removeListener(_onBackupChanged);
    _recorder = recorder;
    _backup = backup;
    _recorder!.addListener(_onRecorder);
    _backup!.addListener(_onBackupChanged);
    _listening = true;
    _scheduleMidnightCatchUp();
    _requestSync(immediate: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleMidnightCatchUp();
      _requestSync(immediate: true);
    }
  }

  void _onRecorder() => _requestSync();

  void _onBackupChanged() {
    final backup = _backup;
    if (backup == null || backup.isLoading) return;
    final configured = backup.isConfigured;
    if (!_backupReady) {
      _backupReady = true;
      _backupWasConfigured = configured;
      if (configured) _requestSync(immediate: true);
      return;
    }
    // Became configured (enabled + folder) — catch up without waiting for
    // the next GPS point (auto-pause can be silent for hours).
    if (configured && !_backupWasConfigured) {
      _backupWasConfigured = true;
      _requestSync(immediate: true);
      return;
    }
    if (!configured) _backupWasConfigured = false;
  }

  void _requestSync({bool immediate = false}) {
    final recorder = _recorder;
    final backup = _backup;
    if (recorder == null || backup == null || !mounted) return;
    _debounce?.cancel();
    if (immediate) {
      unawaited(backup.syncFromRecorder(recorder));
      return;
    }
    // GPS ticks every few seconds; coalesce so Drive is not hammered and
    // a long point list is not copied on every fix.
    _debounce = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      unawaited(backup.syncFromRecorder(recorder));
    });
  }

  /// Fires shortly after local midnight so a recording left open (and often
  /// auto-paused) still uploads yesterday without needing a new GPS fix.
  void _scheduleMidnightCatchUp() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 1);
    _midnightTimer = Timer(next.difference(now), () {
      _requestSync(immediate: true);
      _scheduleMidnightCatchUp();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _midnightTimer?.cancel();
    _recorder?.removeListener(_onRecorder);
    _backup?.removeListener(_onBackupChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Wires up [CarBridge] once both [GpsRecorder] and [RouteRepository] are
/// available from the providers above it, so the Android Auto screen has a
/// live state feed and a way to save a finished ride for the whole app
/// session. No-op on non-Android platforms (see [CarBridge]'s constructor).
class _CarBridgeGate extends StatefulWidget {
  const _CarBridgeGate({required this.child});

  final Widget child;

  @override
  State<_CarBridgeGate> createState() => _CarBridgeGateState();
}

class _CarBridgeGateState extends State<_CarBridgeGate> {
  late final CarBridge _carBridge;

  @override
  void initState() {
    super.initState();
    _carBridge = CarBridge(
      recorder: context.read<GpsRecorder>(),
      routeRepository: context.read<RouteRepository>(),
    );
  }

  @override
  void dispose() {
    _carBridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
