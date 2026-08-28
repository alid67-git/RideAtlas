import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'l10n/gen/app_localizations.dart';
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
import 'widgets/incoming_track_gate.dart';

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
                  seedColor: const Color(0xFFE53935),
                ),
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFFE53935),
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
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
