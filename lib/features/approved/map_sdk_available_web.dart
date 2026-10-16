import 'dart:js_interop';

@JS('google.maps.Map')
external JSFunction? get _mapConstructor;

@JS('hocalistLoadMaps')
external JSPromise<JSBoolean> _loadMaps(JSString key);

/// A browser-restricted public key may be provided at build time. Server keys
/// are never accepted or obtained by this client.
Future<void> initializeMapsSdk() async {
  if (mapSdkAvailable) return;
  const key = String.fromEnvironment('HOCALIST_GOOGLE_MAPS_WEB_API_KEY');
  if (key.isEmpty) return;
  try {
    await _loadMaps(key.toJS).toDart.timeout(const Duration(seconds: 15));
  } catch (_) {
    // Address confirmation and textual directions remain usable on SDK failure.
  }
}

bool get mapSdkAvailable {
  try {
    return _mapConstructor != null;
  } catch (_) {
    // A native API key does not load or authorize the browser Maps SDK.
    return false;
  }
}
