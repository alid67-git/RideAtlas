import 'package:flutter_test/flutter_test.dart';
import 'package:rideatlas/models/base_map_style.dart';

void main() {
  test('tile provider headers stay mutable for TileLayer.putIfAbsent', () {
    // flutter_map's TileLayer calls headers.putIfAbsent('User-Agent', ...)
    // on every non-web construction. A const map throws UnsupportedError and
    // the Android release build paints a blank white screen (v1.4.49).
    final provider = createRideAtlasTileProvider();
    expect(
      () => provider.headers.putIfAbsent('User-Agent', () => 'should-not-win'),
      returnsNormally,
    );
    expect(provider.headers['User-Agent'], kTileUserAgent);
    expect(
      () => provider.headers.putIfAbsent('X-RideAtlas-Test', () => 'ok'),
      returnsNormally,
    );
    expect(provider.headers['X-RideAtlas-Test'], 'ok');
  });
}
