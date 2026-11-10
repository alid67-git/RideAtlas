import 'package:flutter_test/flutter_test.dart';
import 'package:gopro_remote/gopro/models.dart';

void main() {
  test('SavedGoProDevice round-trips JSON', () {
    const original = SavedGoProDevice(
      remoteId: 'AA:BB:CC:DD:EE:FF',
      name: 'GoPro 1234',
      addedAtMs: 1700000000000,
    );
    final restored = SavedGoProDevice.fromJson(original.toJson());
    expect(restored.remoteId, original.remoteId);
    expect(restored.name, original.name);
    expect(restored.addedAtMs, original.addedAtMs);
  });
}
