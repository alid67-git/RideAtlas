import 'package:flutter/material.dart';

import '../screens/home_map_screen.dart';

/// Above the app's Navigator, for anything that needs to push/show
/// something without its own [BuildContext].
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Reaches into the always-mounted Home screen (the base of the navigator
/// stack) from above it - see [HomeMapScreenState.addRoutesToOverlay].
final homeMapScreenKey = GlobalKey<HomeMapScreenState>();
