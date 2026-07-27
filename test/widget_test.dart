import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:rideatlas/main.dart';

void main() {
  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('rideatlas_test');
    Hive.init(hiveDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  testWidgets('shows the empty route list on first launch', (
    WidgetTester tester,
  ) async {
    // Hive's box-open is real file I/O, so it must run outside the fake-async
    // zone that pump()/pumpAndSettle() normally use.
    await tester.runAsync(() async {
      await tester.pumpWidget(const RideAtlasApp());
      for (
        var i = 0;
        i < 20 && find.text('Henüz rota yok').evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });

    expect(find.text('RideAtlas'), findsOneWidget);
    expect(find.text('Henüz rota yok'), findsOneWidget);
    expect(find.text('GPX/KML/KMZ İçe Aktar'), findsWidgets);
  });
}
