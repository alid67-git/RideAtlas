import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'build_info.dart';
import 'l10n/gen/app_localizations.dart';
import 'repositories/locale_controller.dart';
import 'repositories/route_repository.dart';
import 'screens/changelog_dialog.dart';
import 'screens/home_map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const RideAtlasApp());
}

/// The build badge lives above the app's Navigator in the widget tree (it's
/// drawn via [MaterialApp.builder], as a sibling of the actual app content),
/// so it can't reach a Navigator by walking up its own context. This key
/// gives it one to open the changelog dialog with.
final _rootNavigatorKey = GlobalKey<NavigatorState>();

class RideAtlasApp extends StatelessWidget {
  const RideAtlasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RouteRepository()..load()),
        ChangeNotifierProvider(create: (_) => LocaleController()..load()),
      ],
      child: Consumer<LocaleController>(
        builder: (context, localeController, _) {
          return MaterialApp(
            title: 'RideAtlas',
            debugShowCheckedModeBanner: false,
            navigatorKey: _rootNavigatorKey,
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
                  supported.any((l) => l.languageCode == deviceLocale.languageCode)) {
                return Locale(deviceLocale.languageCode);
              }
              return const Locale('tr');
            },
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE53935)),
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
            builder: (context, child) {
              return Stack(
                children: [
                  ?child,
                  const Positioned(left: 8, bottom: 8, child: _BuildBadge()),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Small always-on-screen label showing [kAppBuildLabel], so it's obvious at
/// a glance which build a given browser tab/dev server is actually running.
/// Tapping it opens the full version history (see [ChangelogDialog]).
class _BuildBadge extends StatelessWidget {
  const _BuildBadge();

  void _showChangelog() {
    final context = _rootNavigatorKey.currentContext;
    if (context == null) return;
    showDialog<void>(context: context, builder: (_) => const ChangelogDialog());
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _showChangelog,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                kAppBuildLabel,
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
              Text(
                'Geliştiren: Ali Dinçer',
                style: TextStyle(color: Colors.white70, fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
