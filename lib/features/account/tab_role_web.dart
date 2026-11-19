import 'dart:js_interop';

@JS('sessionStorage.getItem')
external String? _get(String key);
@JS('sessionStorage.setItem')
external void _set(String key, String value);
@JS('sessionStorage.removeItem')
external void _remove(String key);
@JS('localStorage.getItem')
external String? _getShared(String key);
@JS('localStorage.setItem')
external void _setShared(String key, String value);
@JS('localStorage.removeItem')
external void _removeShared(String key);

String _key(String userId) => 'hocalist.activeRole.$userId';

String? readRole(String userId, String? signIn) {
  try {
    final key = _key(userId);
    final tab = _get(key);
    // Migrate roles saved by the earlier tab-only preview.
    if (tab == 'buyer' || tab == 'seller') return tab;
    if (signIn == null) return null;
    final prefix = '$signIn/';
    for (final saved in [tab, _getShared(key)]) {
      if (saved != null && saved.startsWith(prefix)) {
        return saved.substring(prefix.length);
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

void saveRole(String userId, String role, String? signIn) {
  try {
    final key = _key(userId);
    final value = signIn == null ? role : '$signIn/$role';
    _set(key, value);
    if (signIn != null) _setShared(key, value);
  } catch (_) {
    // Role switching still works when the browser disables storage.
  }
}

void clearRole(String userId) {
  try {
    _remove(_key(userId));
    _removeShared(_key(userId));
  } catch (_) {
    // Browser storage is optional.
  }
}
