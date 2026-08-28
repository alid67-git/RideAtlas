import 'package:flutter/material.dart';

/// Above the app's Navigator, for anything that needs to push/show
/// something without its own [BuildContext].
final rootNavigatorKey = GlobalKey<NavigatorState>();
