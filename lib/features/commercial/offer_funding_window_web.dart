import 'dart:js_interop';

@JS('window.open')
external _Popup? _open(String url, String target);
@JS('localStorage.getItem')
external String? _read(String key);
@JS('localStorage.removeItem')
external void _remove(String key);

extension type _Popup(JSObject _) implements JSObject {
  external bool get closed;
  external set opener(JSAny? value);
  external _Location get location;
  external void close();
}
extension type _Location(JSObject _) implements JSObject {
  external void replace(String url);
}

class OfferFundingWindow {
  _Popup? _popup;
  bool open() {
    _popup = _open('about:blank', '_blank');
    _popup?.opener = null;
    return _popup != null;
  }

  Future<bool> navigate(Uri url) async {
    if (_popup == null || _popup!.closed) return false;
    _popup!.location.replace(url.toString());
    return true;
  }

  String? returned(String setup) {
    final key = 'hocalist.offer-return.$setup';
    final value = _read(key);
    if (value != null) _remove(key);
    return value ?? (_popup?.closed == true ? 'closed' : null);
  }

  void close() => _popup?.close();
}
