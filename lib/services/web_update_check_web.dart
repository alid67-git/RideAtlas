import 'dart:js_interop';

@JS('rideAtlasCheckWebUpdate')
external JSPromise<JSString> _rideAtlasCheckWebUpdate();

/// Asks [web/app_update.js] to probe the service worker. Resolves to
/// `available`, `upToDate`, `failed`, or `unsupported`.
Future<String> checkWebUpdate() async {
  try {
    final result = await _rideAtlasCheckWebUpdate().toDart;
    return result.toDart;
  } catch (_) {
    return 'failed';
  }
}
