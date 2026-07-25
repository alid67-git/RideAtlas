import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'build_info.dart';
import 'repositories/route_repository.dart';
import 'screens/route_list_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const RideAtlasApp());
}

class RideAtlasApp extends StatelessWidget {
  const RideAtlasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RouteRepository()..load(),
      child: MaterialApp(
        title: 'RideAtlas',
        debugShowCheckedModeBanner: false,
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
        home: const RouteListScreen(),
        builder: (context, child) {
          return Stack(
            children: [
              ?child,
              const Positioned(left: 8, bottom: 8, child: IgnorePointer(child: _BuildBadge())),
            ],
          );
        },
      ),
    );
  }
}

/// Small always-on-screen label showing [kAppBuildLabel], so it's obvious at
/// a glance which build a given browser tab/dev server is actually running.
class _BuildBadge extends StatelessWidget {
  const _BuildBadge();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          kAppBuildLabel,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }
}
