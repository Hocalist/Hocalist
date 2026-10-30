import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hocalist/features/commercial/native_billing_navigation.dart';

void main() {
  test('native billing uses authenticated body transport and puts only an opaque ticket in the fragment', () async {
    final ticket = 'a' * 100;
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://www.hocalist.com/api/session/native');
      expect(request.method, 'POST');
      expect(request.headers['Authorization'], 'Bearer synthetic-secret');
      return http.Response('{"ticket":"$ticket"}', 200);
    });
    final destination = await nativeBillingDestination('synthetic-secret', client: client);
    expect(destination.query, isEmpty);
    expect(destination.fragment, 'ticket=$ticket');
    expect(destination.toString(), isNot(contains('synthetic-secret')));
    client.close();
  });
  test('failed admission does not silently open anonymous billing', () async {
    final client = MockClient((_) async => http.Response('{}', 503));
    await expectLater(nativeBillingDestination('synthetic', client: client), throwsStateError);
    client.close();
  });
}
