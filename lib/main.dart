import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'repositories/route_repository.dart';
import 'screens/route_list_screen.dart';

void main() {
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
      ),
    );
  }
}
