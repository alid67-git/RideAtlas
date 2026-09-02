import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rideatlas/services/incoming_track_opener.dart';

void main() {
  test('parseForTest accepts Uint8List and List<int>', () {
    final a = IncomingTrackOpener.parseForTest({
      'name': 'ride.gpx',
      'bytes': Uint8List.fromList([60, 103]),
    });
    expect(a?.name, 'ride.gpx');
    expect(a?.bytes, [60, 103]);

    final b = IncomingTrackOpener.parseForTest({
      'name': 'ride.gpx',
      'bytes': [60, 103, 112],
    });
    expect(b?.bytes.length, 3);
  });

  test('parseForTest rejects empty name or bytes', () {
    expect(IncomingTrackOpener.parseForTest({'name': '', 'bytes': [1]}), isNull);
    expect(
      IncomingTrackOpener.parseForTest({'name': 'a.gpx', 'bytes': Uint8List(0)}),
      isNull,
    );
  });
}
