import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:rideatlas/main.dart';

void main() {
  late Directory hiveDir;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('rideatlas_test');
    Hive.init(hiveDir.path);
    // The home screen renders a real FlutterMap, whose tile provider tries
    // to set up on-disk caching via path_provider - unmocked in the test
    // VM (it's a genuine platform channel), so give it a directory to use.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      return hiveDir.path;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    await Hive.deleteFromDisk();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  testWidgets('opens on the home map, then shows the empty route list', (
    WidgetTester tester,
  ) async {
    // Hive's box-open is real file I/O, so it must run outside the fake-async
    // zone that pump()/pumpAndSettle() normally use.
    await tester.runAsync(() async {
      await tester.pumpWidget(const RideAtlasApp());
      for (
        var i = 0;
        i < 20 && find.byIcon(Icons.list).evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });

    // The home screen is a live map (no geolocation in the test harness, so
    // no location marker) with a list icon leading to the saved routes.
    expect(find.byIcon(Icons.list), findsOneWidget);

    await tester.tap(find.byIcon(Icons.list));
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 20 && find.text('No routes yet').evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });

    // The test harness's default locale is en_US, which our
    // localeResolutionCallback resolves to English (a supported locale).
    expect(find.text('RideAtlas'), findsOneWidget);
    expect(find.text('No routes yet'), findsOneWidget);
    expect(find.text('Import GPX/KML/KMZ'), findsWidgets);
  });
}
