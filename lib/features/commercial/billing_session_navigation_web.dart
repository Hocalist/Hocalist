import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('document.createElement')
external JSObject _createElement(JSString name);
@JS('document.body.appendChild')
external void _appendToBody(JSObject element);

bool submitBillingSession(Uri destination, String accessToken, String userId) {
  // Fixed first-party destination. Never place authentication in a URL.
  if (destination.scheme != 'https' ||
      !{'hocalist.com', 'www.hocalist.com'}.contains(destination.host) ||
      destination.hasPort ||
      destination.userInfo.isNotEmpty) {
    return false;
  }
  final form = _createElement('form'.toJS);
  form.setProperty('method'.toJS, 'POST'.toJS);
  form.setProperty('hidden'.toJS, true.toJS);
  form.setProperty(
    'action'.toJS,
    'https://www.hocalist.com/api/session/app'.toJS,
  );
  form.setProperty('target'.toJS, '_self'.toJS);
  for (final entry in {
    'access_token': accessToken,
    'user_id': userId,
  }.entries) {
    final field = _createElement('input'.toJS);
    field.setProperty('type'.toJS, 'hidden'.toJS);
    field.setProperty('name'.toJS, entry.key.toJS);
    field.setProperty('value'.toJS, entry.value.toJS);
    form.callMethod<JSAny?>('appendChild'.toJS, field);
  }
  _appendToBody(form);
  form.callMethod<JSAny?>('submit'.toJS);
  return true;
}
