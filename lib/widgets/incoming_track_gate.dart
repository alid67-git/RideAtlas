import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../navigation/root_navigator.dart';
import '../repositories/route_repository.dart';
import '../screens/map_screen.dart';
import '../services/incoming_track_opener.dart';

/// Listens for Android "Open with" / share-sheet GPX/KML/KMZ files and
/// imports them into [RouteRepository], then opens the route map. Lives
/// above the Navigator (see main.dart) so a cold-start VIEW intent still
/// has a place to push once MaterialApp is ready.
class IncomingTrackGate extends StatefulWidget {
  const IncomingTrackGate({super.key, required this.child});

  final Widget child;

  @override
  State<IncomingTrackGate> createState() => _IncomingTrackGateState();
}

class _IncomingTrackGateState extends State<IncomingTrackGate> {
  StreamSubscription<IncomingTrackFile>? _sub;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    await IncomingTrackOpener.start();
    if (!mounted) return;
    _sub = IncomingTrackOpener.stream.listen(_onFile);
  }

  Future<void> _onFile(IncomingTrackFile file) async {
    if (_importing) return;
    _importing = true;
    try {
      final repo = context.read<RouteRepository>();
      // Wait until the route index has finished loading so we don't race
      // the cold-start Hive load and lose the import, or push onto a
      // half-built navigator.
      while (repo.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted) return;
      }
      final route = await repo.importFromBytes(
        bytes: file.bytes,
        suggestedFileName: file.name,
      );
      if (!mounted) return;
      final nav = rootNavigatorKey.currentState;
      if (nav == null) return;
      await nav.push(
        MaterialPageRoute(builder: (_) => RouteMapScreen(routeId: route.id)),
      );
    } on FormatException {
      _snack((l10n) => l10n.trackHasNoPoints);
    } catch (e) {
      _snack((l10n) => l10n.importFailedGeneric('$e'));
    } finally {
      _importing = false;
    }
  }

  void _snack(String Function(AppLocalizations l10n) message) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    final l10n = AppLocalizations.of(ctx);
    if (l10n == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(message(l10n))));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
