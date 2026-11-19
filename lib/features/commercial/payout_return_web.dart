import 'dart:js_interop';

@JS('sessionStorage.setItem')
external void _set(String key, String value);
@JS('sessionStorage.getItem')
external String? _get(String key);
@JS('sessionStorage.removeItem')
external void _remove(String key);
@JS('history.state')
external JSAny? get _historyState;
@JS('history.replaceState')
external void _replaceState(JSAny? state, String title, String url);

const _key = 'hocalist.buyer_payout_return';

void rememberPayoutReturn(String userId) {
  final expires = DateTime.now().add(const Duration(hours: 24));
  _set(_key, '$userId/${expires.millisecondsSinceEpoch}');
}

bool takePayoutReturn(String? userId) {
  if (userId == null) return false;
  final uri = Uri.base;
  final explicit = uri.queryParameters['returnTo'] == 'buyer-rewards';
  if (explicit) {
    final query = Map.of(uri.queryParameters)..remove('returnTo');
    final clean = uri.replace(queryParameters: query);
    _replaceState(_historyState, '', clean.toString());
  }
  try {
    final parts = _get(_key)?.split('/');
    clearPayoutReturn();
    if (parts == null) return explicit;
    if (parts.length != 2 || parts.first != userId) return false;
    final expires = int.tryParse(parts.last) ?? 0;
    return expires > DateTime.now().millisecondsSinceEpoch;
  } catch (_) {
    return explicit;
  }
}

void clearPayoutReturn() {
  try {
    _remove(_key);
  } catch (_) {
    // Some browsers disable session storage.
  }
}
